@preconcurrency import AppKit
import Foundation

enum AppUpdateInstaller {
    @MainActor
    static func installAndRelaunch(from diskImageURL: URL, failureTitle: String, failureMessage: String) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vellum-install-\(UUID().uuidString).zsh")
        let script = installScript(
            diskImageURL: diskImageURL,
            destinationURL: destinationURL(for: Bundle.main.bundleURL),
            currentProcessID: ProcessInfo.processInfo.processIdentifier,
            failureTitle: failureTitle,
            failureMessage: failureMessage
        )

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()

        NSApp.terminate(nil)
        // A canceled termination leaves the helper waiting for an unrelated later quit.
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    static func destinationURL(for bundleURL: URL, onReadOnlyVolume: Bool? = nil) -> URL {
        let installedURL = bundleURL.resolvingSymlinksInPath()
        let isReadOnly = onReadOnlyVolume
            ?? (try? installedURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly)
            ?? false
        return isReadOnly ? URL(fileURLWithPath: "/Applications/Vellum.app") : installedURL
    }

    static func installScript(
        diskImageURL: URL,
        destinationURL: URL,
        currentProcessID: Int32,
        failureTitle: String = "Unable to install Vellum",
        failureMessage: String = "The update was downloaded, but Vellum could not replace the installed app. Open the disk image and install it manually."
    ) -> String {
        """
        #!/bin/zsh
        set -u

        DMG=\(shellQuoted(diskImageURL.path))
        DEST=\(shellQuoted(destinationURL.path))
        PID=\(currentProcessID)
        FAILURE_TITLE=\(shellQuoted(failureTitle))
        FAILURE_MESSAGE=\(shellQuoted(failureMessage))
        LOG="${TMPDIR:-/tmp}/vellum-update.log"
        INSTALL_SUCCEEDED=0
        STAGING_DIR=""

        fail() {
          /usr/bin/osascript - "$FAILURE_TITLE" "$FAILURE_MESSAGE" <<'APPLESCRIPT'
        on run argv
          display alert (item 1 of argv) message (item 2 of argv)
        end run
        APPLESCRIPT
          /usr/bin/open "$DMG"
          exit 1
        }

        while /bin/kill -0 "$PID" >/dev/null 2>&1; do
          /bin/sleep 0.25
        done

        MOUNT_DIR="$(/usr/bin/mktemp -d /tmp/vellum-update.XXXXXX)" || fail
        cleanup() {
          if [[ -n "$STAGING_DIR" ]]; then
            if [[ "$INSTALL_SUCCEEDED" != "1" && -d "$STAGING_DIR/previous.app" ]]; then
              if ! { /bin/rm -rf "$DEST" && /bin/mv "$STAGING_DIR/previous.app" "$DEST"; } >> "$LOG" 2>&1; then
                # Preserve the backup for manual recovery if rollback fails.
                /usr/bin/open "$STAGING_DIR" >> "$LOG" 2>&1 || true
                STAGING_DIR=""
              fi
            fi
            if [[ -n "$STAGING_DIR" ]]; then
              /bin/rm -rf "$STAGING_DIR"
            fi
          fi
          /usr/bin/hdiutil detach "$MOUNT_DIR" >> "$LOG" 2>&1 || true
          /bin/rm -rf "$MOUNT_DIR"
          if [[ "$INSTALL_SUCCEEDED" == "1" ]]; then
            /bin/rm -f "$DMG" >> "$LOG" 2>&1 || true
          fi
        }
        trap cleanup EXIT
        trap 'exit 1' HUP INT TERM

        /usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >> "$LOG" 2>&1 || fail

        if [[ ! -d "$MOUNT_DIR/Vellum.app" ]]; then
          fail
        fi

        ARCH="$(/usr/bin/uname -m)"
        if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
          ARCH="arm64"
        fi
        /usr/bin/lipo "$MOUNT_DIR/Vellum.app/Contents/MacOS/Vellum" -verify_arch "$ARCH" >> "$LOG" 2>&1 || fail

        STAGING_DIR="$(/usr/bin/mktemp -d "${DEST:h}/.vellum-update.XXXXXX")" || fail
        /usr/bin/ditto "$MOUNT_DIR/Vellum.app" "$STAGING_DIR/Vellum.app" >> "$LOG" 2>&1 || fail
        if [[ -e "$DEST" ]]; then
          /bin/mv "$DEST" "$STAGING_DIR/previous.app" >> "$LOG" 2>&1 || fail
        fi
        /bin/mv "$STAGING_DIR/Vellum.app" "$DEST" >> "$LOG" 2>&1 || fail
        /usr/bin/open "$DEST" >> "$LOG" 2>&1 || fail
        INSTALL_SUCCEEDED=1
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
