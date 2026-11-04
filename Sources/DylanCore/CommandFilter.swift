import Foundation

/// Which shell commands become activities. PRD §F4 / FR-10.
public struct CommandFilter: Sendable, Equatable {
    public static let defaultIgnore: [String] = [
        // Interactive
        "vim", "nvim", "vi", "nano", "less", "more", "man", "top", "htop", "btop", "ssh", "mosh",
        "tmux", "screen", "claude", "codex", "watch", "tail -f", "fzf", "lazygit",
        // Servers (watched by the Port feature instead)
        "npm run dev", "npm start", "pnpm dev", "pnpm run dev", "yarn dev", "bun dev", "bun run dev",
        "vite", "next dev", "rails s", "rails server", "docker compose up", "docker-compose up",
    ]

    /// Seconds a command must run before it appears (and before its result is shown).
    public var threshold: TimeInterval
    public var ignore: [String]

    public init(threshold: TimeInterval = 10, ignore: [String] = CommandFilter.defaultIgnore) {
        self.threshold = threshold; self.ignore = ignore
    }

    /// True when the command should never be tracked.
    /// A pattern matches on whole words from the start (after `sudo`/env assignments),
    /// or anywhere for multi-word patterns such as `tail -f`.
    public func isIgnored(_ command: String) -> Bool {
        let words = Self.words(command)
        guard !words.isEmpty else { return true }
        for pattern in ignore {
            let p = pattern.split(separator: " ").map(String.init)
            guard !p.isEmpty else { continue }
            if words.count >= p.count, Array(words.prefix(p.count)) == p { return true }
            if p.count > 1, words.count >= p.count {
                for i in 0...(words.count - p.count) where Array(words[i..<(i + p.count)]) == p { return true }
            }
        }
        return false
    }

    public func shouldShowRunning(elapsed: TimeInterval) -> Bool { elapsed >= threshold }

    /// Results are shown only for long commands and, by default, only while the terminal is in the background.
    public func shouldShowResult(duration: TimeInterval, terminalFrontmost: Bool, always: Bool) -> Bool {
        duration >= threshold && (always || !terminalFrontmost)
    }

    static func words(_ command: String) -> [String] {
        var w = TextRules.singleLine(command).split(separator: " ").map(String.init)
        while let f = w.first, f == "sudo" || f == "time" || f == "exec" || f == "command" ||
                f.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil {
            w.removeFirst()
        }
        if let f = w.first { w[0] = (f as NSString).lastPathComponent }
        return w
    }
}
