@preconcurrency import AppKit
import Foundation

enum AppUpdateInstaller {
    @MainActor
    static func installAndRelaunch(from diskImageURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vellum-install-\(UUID().uuidString).zsh")
        let script = installScript(
            diskImageURL: diskImageURL,
            destinationURL: URL(fileURLWithPath: "/Applications/Vellum.app"),
            currentProcessID: ProcessInfo.processInfo.processIdentifier
        )

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()

        NSApp.terminate(nil)
    }

    private static func installScript(
        diskImageURL: URL,
        destinationURL: URL,
        currentProcessID: Int32
    ) -> String {
        """
        #!/bin/zsh
        set -u

        DMG=\(shellQuoted(diskImageURL.path))
        DEST=\(shellQuoted(destinationURL.path))
        PID=\(currentProcessID)
        LOG="${TMPDIR:-/tmp}/vellum-update.log"

        fail() {
          /usr/bin/osascript -e 'display alert "Unable to install Vellum" message "The update was downloaded, but Vellum could not copy it to Applications. Open the disk image and install it manually."'
          /usr/bin/open "$DMG"
          exit 1
        }

        while /bin/kill -0 "$PID" >/dev/null 2>&1; do
          /bin/sleep 0.25
        done

        MOUNT_DIR="$(/usr/bin/mktemp -d /tmp/vellum-update.XXXXXX)" || fail
        cleanup() {
          /usr/bin/hdiutil detach "$MOUNT_DIR" >> "$LOG" 2>&1 || true
          /bin/rm -rf "$MOUNT_DIR"
        }
        trap cleanup EXIT

        /usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >> "$LOG" 2>&1 || fail

        if [[ ! -d "$MOUNT_DIR/Vellum.app" ]]; then
          fail
        fi

        /bin/rm -rf "$DEST" >> "$LOG" 2>&1 || fail
        /usr/bin/ditto "$MOUNT_DIR/Vellum.app" "$DEST" >> "$LOG" 2>&1 || fail
        /usr/bin/open "$DEST" >> "$LOG" 2>&1 || fail
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
