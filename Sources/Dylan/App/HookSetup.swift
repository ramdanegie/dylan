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
        /// File content the diff was computed from; apply refuses if the file changed since.
        var base: Data?
    }

    enum SetupError: LocalizedError {
        case changedSinceReview, unreadable(String)
        var errorDescription: String? {
            switch self {
            case .changedSinceReview: return L("hooks.changed")
            case .unreadable(let f): return L("setup.unreadable", f)
            }
        }
    }

    static func previewInstall() throws -> Preview {
        let old = try? Data(contentsOf: settingsURL)
        let r = try HookInstaller.install(into: old, command: command)
        let before = String(decoding: try HookInstaller.normalized(old), as: UTF8.self)
        return Preview(diff: LineDiff.diff(old: before, new: String(decoding: r.json, as: UTF8.self)), newData: r.json,
                       summary: L("hooks.summary", r.added + r.updated, 0), base: old)
    }

    static func previewUninstall() throws -> Preview {
        guard let old = try? Data(contentsOf: settingsURL) else { throw CocoaError(.fileNoSuchFile) }
        let r = try HookInstaller.uninstall(from: old)
        let before = String(decoding: try HookInstaller.normalized(old), as: UTF8.self)
        return Preview(diff: LineDiff.diff(old: before, new: String(decoding: r.json, as: UTF8.self)), newData: r.json,
                       summary: L("hooks.summary", 0, r.removed), base: old)
    }

    /// Writes after the user approved the diff. Returns the backup path.
    @discardableResult
    static func apply(_ p: Preview) throws -> URL? {
        let fm = FileManager.default
        // Claude Code may have written the file while the diff was open: never overwrite unseen changes.
        guard (try? Data(contentsOf: settingsURL)) == p.base else { throw SetupError.changedSinceReview }
        // Dotfile setups symlink settings.json; write through to the real file instead of replacing the link.
        let target = settingsURL.resolvingSymlinksInPath()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fm.fileExists(atPath: target.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd-HHmmss"
            let b = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.dylan-backup-\(f.string(from: Date()))")
            try fm.copyItem(at: target, to: b)
            backup = b
        }
        // Validate before writing: must parse back as a JSON object.
        _ = try HookInstaller.normalized(p.newData)
        try p.newData.write(to: target, options: .atomic)
        return backup
    }

    // MARK: Shell integration (PRD §F4)

    static var zshrcURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc") }

    /// Absolute, quoted CLI path: `~/.local/bin` is not on the default macOS PATH, and `[[ -x ]]`
    /// keeps new shells quiet if the app is moved or deleted.
    static var zshLine: String {
        let q = "'" + cliPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[[ -x \(q) ]] && eval \"$(\(q) shell-init zsh)\""
    }

    static var shellIntegrationInstalled: Bool {
        (try? Data(contentsOf: zshrcURL))?.range(of: Data("shell-init zsh".utf8)) != nil
    }

    /// Appends the eval line (with a backup). Never rewrites the user's file: an unreadable
    /// `.zshrc` is an error, and appending goes through symlinks (dotfiles) untouched.
    static func installShellIntegration() throws {
        try? linkCLI()
        let fm = FileManager.default
        var existing = Data()
        if fm.fileExists(atPath: zshrcURL.path) {
            guard let d = try? Data(contentsOf: zshrcURL) else { throw SetupError.unreadable("~/.zshrc") }
            existing = d
        }
        guard existing.range(of: Data("shell-init zsh".utf8)) == nil else { return }
        if !existing.isEmpty {
            let b = zshrcURL.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent(".zshrc.dylan-backup")
            try? fm.removeItem(at: b)
            try existing.write(to: b)
        }
        let needsNewline = !existing.isEmpty && existing.last != 0x0A
        let block = (needsNewline ? "\n" : "") + "\n# Dylan: track long commands in the notch\n\(zshLine)\n"
        if !fm.fileExists(atPath: zshrcURL.path) { fm.createFile(atPath: zshrcURL.path, contents: nil, attributes: [.posixPermissions: 0o644]) }
        let h = try FileHandle(forWritingTo: zshrcURL)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(block.utf8))
    }

    static var localBinCLI: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/dylan") }

    /// Links ~/.local/bin/dylan. Only replaces a link that already points at a Dylan build (or nowhere);
    /// a real file or someone else's link is left alone.
    static func linkCLI() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: localBinCLI.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let dest = try? fm.destinationOfSymbolicLink(atPath: localBinCLI.path) {
            if dest == cliPath { return }
            let dangling = !fm.fileExists(atPath: dest)
            guard dangling || dest.contains("Dylan.app/") || dest.hasSuffix("/dylan-cli") else { throw SetupError.unreadable(localBinCLI.path) }
            try fm.removeItem(at: localBinCLI)
        } else if fm.fileExists(atPath: localBinCLI.path) {
            throw SetupError.unreadable(localBinCLI.path)
        }
        try fm.createSymbolicLink(atPath: localBinCLI.path, withDestinationPath: cliPath)
    }
}
