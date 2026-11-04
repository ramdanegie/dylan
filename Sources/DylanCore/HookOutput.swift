import Foundation

/// What `dylan hook claude` prints for a PermissionRequest. Every other event stays silent,
/// because stdout of some events (SessionStart, UserPromptSubmit) is injected into Claude's context.
public enum HookOutput {
    /// nil = print nothing, so Claude Code shows its normal terminal prompt.
    public static func permissionRequest(_ reply: PermissionReply) -> Data? {
        var decision: [String: Any]
        switch reply.decision {
        case .passthrough: return nil
        case .allow: decision = ["behavior": "allow"]
        case .deny: decision = ["behavior": "deny", "message": reply.message ?? "Ditolak dari notch Dylan"]
        }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    }
}

/// Output of `dylan shell-init zsh`. PRD §2.6. Both hooks run in the background (`&!`) so the prompt never waits.
public enum ShellInit {
    public static func zsh(cliPath: String) -> String {
        let cli = "'" + cliPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // The command text goes through stdin, not argv, so `ps` never shows it (it may contain secrets).
        return """
        # Dylan shell integration (eval "$(dylan shell-init zsh)")
        if [[ -z "$_DYLAN_SHELL_INIT" ]]; then
          _DYLAN_SHELL_INIT=1
          typeset -gi _dylan_seq=0
          _dylan_preexec() { (( _dylan_seq++ )); _dylan_cmd=1; print -rn -- "$1" | \(cli) _shell start --shell-pid $$ --seq $_dylan_seq --cwd "$PWD" >/dev/null 2>&1 &! }
          _dylan_precmd()  { local s=$?; if [[ -n $_dylan_cmd ]]; then \(cli) _shell end --shell-pid $$ --seq $_dylan_seq --status $s >/dev/null 2>&1 &!; fi; unset _dylan_cmd }
          autoload -Uz add-zsh-hook
          add-zsh-hook preexec _dylan_preexec
          add-zsh-hook precmd  _dylan_precmd
        fi

        """
    }
}
