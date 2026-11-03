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

    // MARK: Codex CLI (FR-32)

    static var codexURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml") }
    static var codexInstalled: Bool { CodexConfig.isInstalled((try? String(contentsOf: codexURL, encoding: .utf8)) ?? "") }
    static var codexAvailable: Bool { Tool.path("codex") != nil || FileManager.default.fileExists(atPath: codexURL.deletingLastPathComponent().path) }

    static func previewCodex(install: Bool) throws -> (Preview, URL) {
        let fm = FileManager.default
        var oldText = ""
        if fm.fileExists(atPath: codexURL.path) {
            guard let t = try? String(contentsOf: codexURL, encoding: .utf8) else { throw SetupError.unreadable("~/.codex/config.toml") }
            oldText = t
        }
        let new = install ? CodexConfig.install(oldText, cliPath: cliPath) : CodexConfig.uninstall(oldText)
        let p = Preview(diff: LineDiff.diff(old: oldText, new: new), newData: Data(new.utf8),
                        summary: install ? L("codex.summaryInstall") : L("codex.summaryRemove"), base: oldText.isEmpty ? nil : Data(oldText.utf8))
        return (p, codexURL)
    }

    static func applyCodex(_ p: Preview) throws { try applyFile(p, to: codexURL) }

    /// Backup + re-check + atomic write, like settings.json. Empty content removes the file (a plugin we own).
    static func applyFile(_ p: Preview, to url: URL) throws {
        let fm = FileManager.default
        guard (try? Data(contentsOf: url)) == p.base else { throw SetupError.changedSinceReview }
        let target = url.resolvingSymlinksInPath()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
            let b = target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + ".dylan-backup")
            try? fm.removeItem(at: b)
            try fm.copyItem(at: target, to: b)
        }
        if p.newData.isEmpty { try? fm.removeItem(at: target); return }
        try p.newData.write(to: target, options: .atomic)
    }

    // MARK: Cursor & OpenCode (FR-34)

    static var cursorURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/hooks.json") }
    static var cursorInstalled: Bool { AgentAdapter.cursorInstalled(try? Data(contentsOf: cursorURL)) }
    static var cursorAvailable: Bool {
        Tool.path("cursor-agent") != nil || FileManager.default.fileExists(atPath: cursorURL.deletingLastPathComponent().path)
    }

    static func previewCursor(install: Bool) throws -> Preview {
        let old = try? Data(contentsOf: cursorURL)
        if old != nil, (try? AgentAdapter.cursorRootIsValid(old)) != true { throw SetupError.unreadable("~/.cursor/hooks.json") }
        let new = install ? try AgentAdapter.installCursor(old, command: AgentAdapter.cursorCommand(cliPath: cliPath))
                          : try AgentAdapter.uninstallCursor(old ?? Data())
        return Preview(diff: LineDiff.diff(old: old.map { String(decoding: $0, as: UTF8.self) } ?? "", new: String(decoding: new, as: UTF8.self)),
                       newData: new, summary: install ? L("agentsOther.summaryInstall", "Cursor") : L("agentsOther.summaryRemove", "Cursor"), base: old)
    }

    static var opencodeURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/plugins/dylan.js") }
    static var opencodeInstalled: Bool { FileManager.default.fileExists(atPath: opencodeURL.path) }
    static var opencodeAvailable: Bool {
        Tool.path("opencode") != nil || FileManager.default.fileExists(atPath: opencodeURL.deletingLastPathComponent().deletingLastPathComponent().path)
    }

    static func previewOpenCode(install: Bool) -> Preview {
        let old = try? Data(contentsOf: opencodeURL)
        let new = install ? AgentAdapter.opencodePlugin(cliPath: cliPath) : ""
        return Preview(diff: LineDiff.diff(old: old.map { String(decoding: $0, as: UTF8.self) } ?? "", new: new), newData: Data(new.utf8),
                       summary: install ? L("agentsOther.summaryInstall", "OpenCode") : L("agentsOther.summaryRemove", "OpenCode"), base: old)
    }

    static var mcpCommand: String {
        "claude mcp add dylan -- '" + cliPath.replacingOccurrences(of: "'", with: "'\\''") + "' mcp"
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
