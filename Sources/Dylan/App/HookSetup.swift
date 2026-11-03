import DylanCore
import Foundation

/// Edits user config files: always backup, diff, approval, atomic write (PRD §2.8).
enum HookSetup {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Path of the bundled CLI (`Dylan.app/Contents/Helpers/dylan`), or the dev build next to the app binary.
    static var cliPath: String {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/dylan").path
        if FileManager.default.isExecutableFile(atPath: helpers) { return helpers }
        let dev = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("dylan-cli").path
        return dev
    }

    static var command: String { HookInstaller.command(cliPath: cliPath) }

    static func status() -> HookInstaller.Status {
        (try? HookInstaller.status(try? Data(contentsOf: settingsURL), command: command)) ?? .notInstalled
    }

    struct Preview {
        var diff: [LineDiff.Line]
        var newData: Data
        var summary: String
    }

    static func previewInstall() throws -> Preview {
        let old = try? Data(contentsOf: settingsURL)
        let r = try HookInstaller.install(into: old, command: command)
        let before = String(decoding: try HookInstaller.normalized(old), as: UTF8.self)
        return Preview(diff: LineDiff.diff(old: before, new: String(decoding: r.json, as: UTF8.self)), newData: r.json,
                       summary: L("hooks.summary", r.added + r.updated, 0))
    }

    static func previewUninstall() throws -> Preview {
        guard let old = try? Data(contentsOf: settingsURL) else { throw CocoaError(.fileNoSuchFile) }
        let r = try HookInstaller.uninstall(from: old)
        let before = String(decoding: try HookInstaller.normalized(old), as: UTF8.self)
        return Preview(diff: LineDiff.diff(old: before, new: String(decoding: r.json, as: UTF8.self)), newData: r.json,
                       summary: L("hooks.summary", 0, r.removed))
    }

    /// Writes after the user approved the diff. Returns the backup path.
    @discardableResult
    static func apply(_ p: Preview) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fm.fileExists(atPath: settingsURL.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd-HHmmss"
            let b = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.dylan-backup-\(f.string(from: Date()))")
            try fm.copyItem(at: settingsURL, to: b)
            backup = b
        }
        // Validate before writing: must parse back as a JSON object.
        _ = try HookInstaller.normalized(p.newData)
        try p.newData.write(to: settingsURL, options: .atomic)
        return backup
    }

    // MARK: Shell integration (PRD §F4)

    static var zshrcURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc") }
    static let zshLine = #"eval "$(dylan shell-init zsh)""#

    static var shellIntegrationInstalled: Bool {
        ((try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? "").contains("dylan shell-init")
    }

    /// Appends the eval line (with backup) and links the CLI into ~/.local/bin.
    static func installShellIntegration() throws {
        try linkCLI()
        let fm = FileManager.default
        var text = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        guard !text.contains("dylan shell-init") else { return }
        if fm.fileExists(atPath: zshrcURL.path) {
            let b = zshrcURL.deletingLastPathComponent().appendingPathComponent(".zshrc.dylan-backup")
            try? fm.removeItem(at: b)
            try fm.copyItem(at: zshrcURL, to: b)
        }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\n# Dylan: lacak perintah panjang di notch\ncommand -v dylan >/dev/null && \(zshLine)\n"
        try text.write(to: zshrcURL, atomically: true, encoding: .utf8)
    }

    static var localBinCLI: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/dylan") }

    static func linkCLI() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: localBinCLI.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let dest = try? fm.destinationOfSymbolicLink(atPath: localBinCLI.path), dest == cliPath { return }
        if (try? fm.destinationOfSymbolicLink(atPath: localBinCLI.path)) != nil { try fm.removeItem(at: localBinCLI) }
        guard !fm.fileExists(atPath: localBinCLI.path) else { return }   // never overwrite a real file
        try fm.createSymbolicLink(atPath: localBinCLI.path, withDestinationPath: cliPath)
    }
}
