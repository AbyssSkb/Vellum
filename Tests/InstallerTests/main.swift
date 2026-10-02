// Run: swiftc -module-cache-path .build/ModuleCache Sources/Vellum/App/AppUpdateInstaller.swift Sources/Vellum/App/UpdateCancellation.swift Tests/InstallerTests/main.swift -o /tmp/vellum-installer-tests && /tmp/vellum-installer-tests
import Foundation

func quoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("Vellum installer test \(UUID())")
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }

let customInstallation = root.appendingPathComponent("My Apps/Reader.app")
assert(AppUpdateInstaller.destinationURL(for: customInstallation, onReadOnlyVolume: false) == customInstallation)
assert(AppUpdateInstaller.destinationURL(for: customInstallation, onReadOnlyVolume: true).path == "/Applications/Vellum.app")
assert(isUpdateCancellation(CancellationError()))
assert(isUpdateCancellation(URLError(.cancelled)))
assert(isUpdateCancellation(NSError(domain: NSURLErrorDomain, code: -999)))
assert(!isUpdateCancellation(URLError(.timedOut)))
print("Installer destination and update cancellation: passed")

for failure in ["none", "incompatible", "copy", "replace", "relaunch", "rollback"] {
    let directory = root.appendingPathComponent(failure)
    let source = directory.appendingPathComponent("source/Vellum.app")
    let destination = directory.appendingPathComponent("My Apps/Reader.app")
    let diskImage = directory.appendingPathComponent("update.dmg")
    for app in [source, destination] {
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
    }
    try "new".write(to: source.appendingPathComponent("version"), atomically: true, encoding: .utf8)
    try "old".write(to: destination.appendingPathComponent("version"), atomically: true, encoding: .utf8)
    try Data().write(to: diskImage)

    func command(_ name: String, _ body: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/zsh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return quoted(url.path)
    }

    let mount = try command("mount", """
        if [[ "$1" == attach ]]; then
          /usr/bin/ditto \(quoted(source.path)) "${@: -1}/Vellum.app"
        fi
        """)
    let copy = try command("copy", """
        /usr/bin/ditto "$1" "$2" || exit 1
        exit \(failure == "copy" ? 1 : 0)
        """)
    let move = try command("move", """
        if [[ "$2" == \(quoted(destination.path)) ]]; then
          [[ \(quoted(failure)) == replace && "$1" == */Vellum.app ]] && exit 1
          [[ \(quoted(failure)) == rollback && "$1" == */previous.app ]] && exit 1
        fi
        exec /bin/mv "$@"
        """)
    let open = try command("open", """
        if [[ "$1" == \(quoted(destination.path)) ]]; then
          [[ \(quoted(failure)) == relaunch || \(quoted(failure)) == rollback ]] && exit 1
        fi
        exit 0
        """)
    let architecture = try command("architecture", """
        [[ "$1" == */Vellum.app/Contents/MacOS/Vellum && "$2" == -verify_arch && "$3" == arm64 ]] || exit 1
        exit \(failure == "incompatible" ? 1 : 0)
        """)
    let script = AppUpdateInstaller.installScript(
        diskImageURL: diskImage,
        destinationURL: destination,
        currentProcessID: Int32.max
    )
        .replacingOccurrences(of: "/usr/bin/hdiutil", with: mount)
        .replacingOccurrences(of: "/usr/bin/ditto", with: copy)
        .replacingOccurrences(of: "/bin/mv", with: move)
        .replacingOccurrences(of: "/usr/bin/open", with: open)
        .replacingOccurrences(of: "/usr/bin/lipo", with: architecture)
        .replacingOccurrences(of: "/usr/sbin/sysctl", with: "/usr/bin/printf 1")
        .replacingOccurrences(of: "/usr/bin/osascript", with: "/usr/bin/true")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", script]
    try process.run()
    process.waitUntilExit()

    assert((process.terminationStatus == 0) == (failure == "none"), failure)
    assert(manager.fileExists(atPath: diskImage.path) == (failure != "none"), failure)
    let remaining = try manager.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".vellum-update.") }
    if failure == "rollback" {
        assert(remaining.count == 1, "Failed rollback must preserve its backup")
        let backup = remaining[0].appendingPathComponent("previous.app/version")
        let version = try String(contentsOf: backup, encoding: .utf8)
        assert(version == "old")
    } else {
        let version = try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8)
        assert(version == (failure == "none" ? "new" : "old"), failure)
        assert(remaining.isEmpty, "Staging directory should be cleaned up")
    }
    print("Installer \(failure): passed")
}
