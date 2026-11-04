import DylanCore
import Foundation
#if canImport(Darwin)
import Darwin
#endif

// `dylan` CLI. PRD §2.6.
// Rule: when Dylan is not running, commands exit 0 with a note on stderr so user scripts never fail
// because of Dylan. `dylan run` passes through the command's exit code. Hooks are always silent.

let version = "0.1.2"
var args = Array(CommandLine.arguments.dropFirst())

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func usage() -> Never {
    print("""
    dylan \(version) — Live Activity API for the Dylan notch

      dylan activity start <id> --title <t> [--subtitle <s>] [--progress 0..1] [--url <u>]
      dylan activity update <id> [--title <t>] [--subtitle <s>] [--progress 0..1]
      dylan activity end <id> --success | --failure [--detail <d>]
      dylan notify <title> [body]
      dylan shelf add <file…>           put files on the shelf
      dylan run -- <command…>           run as an activity; passes the exit code through
      dylan shell-init zsh              print the zsh integration
      dylan hook claude | codex         called by Claude Code hooks / Codex notify
      dylan hook cursor | opencode      called by Cursor hooks / the OpenCode plugin
      dylan mcp                         MCP server (stdio) with notify, activity, shelf_add
      dylan doctor                      check the app, socket, hooks and shell integration
      dylan debug emit <file.json>      send a fake hook payload (testing)
      dylan debug state                 print the activities on screen (JSON)
    """)
    exit(0)
}

/// Absolute path of this binary, symlinks resolved (argv[0] is just "dylan" when found via PATH).
func selfPath() -> String {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buf, &size) == 0 else { return CommandLine.arguments[0] }
    let path = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let socketPath = Bridge.socketURL.path

/// Sends one message. Returns false when Dylan is not reachable.
@discardableResult
func send(_ m: BridgeMessage, timeout: TimeInterval = 0.5) -> Bool {
    guard let fd = try? UnixSocket.connect(path: socketPath, timeout: timeout) else { return false }
    defer { close(fd) }
    return (try? UnixSocket.write(fd, try m.encodedLine())) != nil
}

func sendOrWarn(_ m: BridgeMessage) {
    if !send(m) { stderr("dylan: the Dylan app is not running; message ignored") }
}

func terminalEnv() -> [String: String] {
    let e = ProcessInfo.processInfo.environment
    var out: [String: String] = [:]
    for k in ["__CFBundleIdentifier", "TERM_PROGRAM", "CLAUDE_PROJECT_DIR"] { out[k] = e[k] }
    out["ppid"] = String(getppid())
    return out
}

func parseProgress(_ s: String?) -> Double? {
    guard let s, let v = Double(s) else { return nil }
    return min(1, max(0, v))
}

// MARK: hook

func hook(source: String) -> Never {
    // Codex passes the event as one JSON argument (notify program), not on stdin.
    if source == "codex" {
        let raw = args.dropFirst().last.map { Data($0.utf8) } ?? FileHandle.standardInput.readDataToEndOfFile()
        if let payload = try? JSONDecoder().decode(JSONValue.self, from: raw) {
            send(.hook(source: "codex", env: terminalEnv(), payload: HookPayload.slimCodex(payload)), timeout: 0.2)
        }
        exit(0)
    }
    // Cursor / OpenCode (FR-34): observation only, translated into the Claude shape.
    if source == "cursor" || source == "opencode" {
        let payload = try? JSONDecoder().decode(JSONValue.self, from: FileHandle.standardInput.readDataToEndOfFile())
        if let payload, let t = source == "cursor" ? AgentAdapter.cursor(payload) : AgentAdapter.opencode(payload) {
            send(.hook(source: source, env: terminalEnv(), payload: HookPayload.slim(t)), timeout: 0.2)
        }
        // Cursor parses stdout; this is printed whether or not Dylan is running.
        if source == "cursor" { print(AgentAdapter.cursorOutput(event: payload?["hook_event_name"]?.string)) }
        exit(0)
    }
    // Fail-open: any problem → exit 0 without output so Claude Code continues normally.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard source == "claude", let payload = try? JSONDecoder().decode(JSONValue.self, from: input) else { exit(0) }
    let slim = HookPayload.slim(payload)
    let env = terminalEnv()
    guard slim["hook_event_name"]?.string == "PermissionRequest" else {
        send(.hook(source: source, env: env, payload: slim), timeout: 0.2)
        exit(0)
    }
    // Wait for the notch. Dylan replies "passthrough" at once when it should not hold the prompt.
    let id = UUID().uuidString
    guard let fd = try? UnixSocket.connect(path: socketPath, timeout: 0.2) else { exit(0) }
    defer { close(fd) }
    guard (try? UnixSocket.write(fd, try BridgeMessage.permissionAsk(requestId: id, source: source, env: env, payload: slim).encodedLine())) != nil
    else { exit(0) }
    UnixSocket.setTimeouts(fd, 55)   // below the 60 s hook timeout installed in settings.json
    guard let line = try? UnixSocket.readLine(fd),
          let reply = try? JSONDecoder().decode(PermissionReply.self, from: line),
          let out = HookOutput.permissionRequest(reply) else { exit(0) }
    FileHandle.standardOutput.write(out)
    exit(0)
}

// MARK: run

func run(_ command: [String]) -> Never {
    guard !command.isEmpty else { stderr("dylan run: no command given"); exit(64) }
    let id = "run-\(getpid())"
    let title = TextRules.commandShortName(command.joined(separator: " "))
    let start = Date()
    send(.activityStart(id: id, title: title, subtitle: FileManager.default.currentDirectoryPath, progress: nil, url: nil))

    var pid: pid_t = 0
    let cargs = command.map { strdup($0) } + [nil]
    defer { cargs.forEach { free($0) } }
    let rc = posix_spawnp(&pid, command[0], nil, nil, cargs, environ)
    guard rc == 0 else {
        send(.activityEnd(id: id, success: false, detail: "could not start"))
        stderr("dylan run: \(command[0]): \(String(cString: strerror(rc)))")
        exit(127)
    }
    // Ctrl-C reaches the child through the terminal's process group; ignore it here so we can report.
    signal(SIGINT, SIG_IGN)
    var status: Int32 = 0
    while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
    let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    let detail = code == 0 ? DurationFormat.result(Date().timeIntervalSince(start))
                           : "exit \(code) · \(DurationFormat.result(Date().timeIntervalSince(start)))"
    send(.activityEnd(id: id, success: code == 0, detail: detail))
    exit(code)
}

// MARK: doctor

func doctor() -> Never {
    func line(_ ok: Bool, _ s: String) { print("\(ok ? "✓" : "✗") \(s)") }
    var reply: PingReply?
    if let fd = try? UnixSocket.connect(path: socketPath, timeout: 0.5) {
        defer { close(fd) }
        if (try? UnixSocket.write(fd, try BridgeMessage.ping.encodedLine())) != nil, let l = try? UnixSocket.readLine(fd) {
            reply = try? JSONDecoder().decode(PingReply.self, from: l)
        }
    }
    line(reply != nil, reply.map { "Dylan app is running (v\($0.version), \($0.profile) profile)" } ?? "Dylan app is not running")
    var st = stat()
    let sockOK = stat(socketPath, &st) == 0 && (st.st_mode & 0o777) == 0o600
    line(sockOK, "Socket \(TextRules.abbreviatePath(socketPath)) \(sockOK ? "(0600)" : "missing or wrong permissions")")

    let me = selfPath()
    line(true, "CLI: \(me)")
    let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    let status = (try? HookInstaller.status(try? Data(contentsOf: settings), command: HookInstaller.command(cliPath: me))) ?? .notInstalled
    switch status {
    case .installed: line(true, "Claude Code hooks installed (8 events)")
    case .needsUpdate: line(false, "Claude Code hooks need an update (app moved?) — open Settings → Agents")
    case .notInstalled: line(false, "Claude Code hooks not installed (optional, Developer profile)")
    }
    let zshrc = (try? String(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc"), encoding: .utf8)) ?? ""
    let hasInit = zshrc.contains("shell-init zsh")
    line(hasInit, hasInit ? "Shell integration found in ~/.zshrc"
         : "Shell integration not set up (optional): Settings → Terminal → Add to ~/.zshrc")
    exit(0)
}

// MARK: main

guard let cmd = args.first else { usage() }
args.removeFirst()

switch cmd {
case "activity":
    guard let sub = args.first, args.count >= 2 else { usage() }
    let id = args[1]
    args.removeFirst(2)
    switch sub {
    case "start":
        guard let title = option("--title") else { stderr("dylan activity start: --title is required"); exit(64) }
        sendOrWarn(.activityStart(id: id, title: title, subtitle: option("--subtitle"),
                                  progress: parseProgress(option("--progress")), url: option("--url")))
    case "update":
        sendOrWarn(.activityUpdate(id: id, title: option("--title"), subtitle: option("--subtitle"),
                                   progress: parseProgress(option("--progress"))))
    case "end":
        let ok = flag("--success"), fail = flag("--failure")
        guard ok != fail else { stderr("dylan activity end: pass --success or --failure"); exit(64) }
        sendOrWarn(.activityEnd(id: id, success: ok, detail: option("--detail")))
    default: usage()
    }
case "shelf":
    guard args.first == "add", args.count >= 2 else { stderr("usage: dylan shelf add <file…>"); exit(64) }
    let paths = args.dropFirst().map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    sendOrWarn(.shelfAdd(paths: Array(paths)))
case "notify":
    guard let title = args.first else { usage() }
    sendOrWarn(.notify(title: title, body: args.count > 1 ? args[1] : nil))
case "run":
    if args.first == "--" { args.removeFirst() }
    run(args)
case "shell-init":
    guard args.first == "zsh" else { stderr("dylan shell-init: only zsh is supported for now"); exit(64) }
    print(ShellInit.zsh(cliPath: selfPath()), terminator: "")
case "_shell":
    // Called in the background by the zsh hooks; never prints.
    guard let sub = args.first else { exit(0) }
    args.removeFirst()
    let pid = Int(option("--shell-pid") ?? "") ?? Int(getppid())
    let seq = Int(option("--seq") ?? "")
    if sub == "start" {
        // Command text arrives on stdin (kept out of argv); --cmd is accepted for older shell-init scripts.
        let c = option("--cmd") ?? String(decoding: FileHandle.standardInput.readData(ofLength: 4096), as: UTF8.self)
        guard !c.isEmpty else { exit(0) }
        send(.shellStart(shellPid: pid, cmd: c, cwd: option("--cwd") ?? "", app: terminalEnv()["__CFBundleIdentifier"], seq: seq), timeout: 0.2)
    } else if sub == "end", let s = Int(option("--status") ?? "") {
        send(.shellEnd(shellPid: pid, status: s, seq: seq), timeout: 0.2)
    }
case "hook":
    hook(source: args.first ?? "")
case "doctor":
    doctor()
case "mcp":
    // MCP server over stdio for Claude Code: `claude mcp add dylan -- <path to dylan> mcp`.
    let server = MCPServer(version: version) { send($0) }
    while let line = readLine(strippingNewline: true) {
        guard !line.isEmpty, let out = server.handle(Data(line.utf8)) else { continue }
        FileHandle.standardOutput.write(out)
    }
    exit(0)
case "debug" where args.first == "state":
    guard let fd = try? UnixSocket.connect(path: socketPath, timeout: 0.5) else { stderr("dylan: the Dylan app is not running"); exit(0) }
    defer { close(fd) }
    if (try? UnixSocket.write(fd, try BridgeMessage.debugState.encodedLine())) != nil, let l = try? UnixSocket.readLine(fd) {
        FileHandle.standardOutput.write(l + Data([0x0A]))
    }
case "debug":
    guard args.first == "emit", args.count >= 2, let data = FileManager.default.contents(atPath: args[1]),
          let payload = try? JSONDecoder().decode(JSONValue.self, from: data) else { usage() }
    sendOrWarn(.hook(source: "claude", env: terminalEnv(), payload: HookPayload.slim(payload)))
case "version", "--version", "-v":
    print(version)
default:
    usage()
}
exit(0)
