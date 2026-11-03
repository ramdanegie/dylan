import Darwin
import Foundation

/// A shell on a pseudo-terminal for the quick terminal (FR-41). posix_spawn with POSIX_SPAWN_SETSID (no fork in a
/// threaded app); the child opens the slave as its first tty, which makes it the controlling terminal, so
/// Ctrl-C (0x03) interrupts the foreground job like in Terminal.
public final class PTY: @unchecked Sendable {
    public let pid: pid_t
    public let master: Int32
    private let lock = NSLock()
    private var closed = false
    private var exited = false
    private var reading = false

    public init?(path: String, args: [String], environment: [String: String], cwd: String, cols: UInt16 = 90, rows: UInt16 = 14) {
        let m = posix_openpt(O_RDWR | O_NOCTTY)
        guard m >= 0, grantpt(m) == 0, unlockpt(m) == 0, let name = ptsname(m) else { if m >= 0 { close(m) }; return nil }
        let slave = String(cString: name)
        // The size sticks only once the slave is open; keep this fd open until the child has it too.
        let s = open(slave, O_RDWR | O_NOCTTY)
        defer { if s >= 0 { close(s) } }
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(s >= 0 ? s : m, TIOCSWINSZ, &size)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // A shell must not inherit the app's blocked or ignored signals (Ctrl-C, SIGPIPE in pipelines).
        var none = sigset_t(), all = sigset_t()
        sigemptyset(&none); sigfillset(&all)
        posix_spawnattr_setsigmask(&attr, &none)
        posix_spawnattr_setsigdefault(&attr, &all)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, slave, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1)
        posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        let argv = ([path] + args).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        guard posix_spawn(&child, path, &actions, &attr, argv, envp) == 0 else { close(m); return nil }
        pid = child
        master = m
    }

    deinit {
        terminate()
        if !reading { close(master) }   // no reader thread will close it
    }

    public func write(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        data.withUnsafeBytes { p in
            var off = 0
            while off < p.count {
                let n = Darwin.write(master, p.baseAddress! + off, p.count - off)
                if n < 0 { if errno == EINTR { continue }; return }
                off += n
            }
        }
    }

    public func resize(cols: UInt16, rows: UInt16) {
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &size)
    }

    /// Blocking: reads until the shell exits, then closes the master. Run it on its own thread.
    /// Only this loop closes the fd, so a terminate() can never let it read a reused descriptor.
    public func readLoop(_ onData: (Data) -> Void) {
        lock.lock(); reading = true; lock.unlock()
        var buf = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(master, &buf, buf.count)
            if n > 0 { onData(Data(buf[0..<n])); continue }
            if n < 0 && errno == EINTR { continue }
            break
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        lock.lock(); exited = true; lock.unlock()
        close(master)
    }

    /// Hangs up the shell and its jobs (the whole process group); SIGKILL after 2 s if something ignores it.
    public func terminate() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
        let pid = self.pid
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let gone = self.exited; self.lock.unlock()
            if !gone { kill(-pid, SIGKILL); kill(pid, SIGKILL) }
        }
    }

    /// The shell's current directory, for handing the session to Terminal or VS Code.
    public var currentDirectory: String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
    }
}
