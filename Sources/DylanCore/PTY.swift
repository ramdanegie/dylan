import Darwin
import Foundation

/// A shell on a pseudo-terminal for the quick terminal (FR-41), started with forkpty so the slave is the shell's
/// controlling terminal and Ctrl-C (0x03) interrupts the foreground job like in Terminal.
public final class PTY: @unchecked Sendable {
    public let pid: pid_t
    public let master: Int32
    private let lock = NSLock()
    private var closed = false
    private var exited = false
    private var reading = false

    public init?(path: String, args: [String], environment: [String: String], cwd: String, cols: UInt16 = 90, rows: UInt16 = 14) {
        // Everything the child needs is built before fork: after fork it may only make async-signal-safe calls.
        let argv = ([path] + args).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let cpath = strdup(path), ccwd = strdup(cwd)
        defer { argv.forEach { free($0) }; envp.forEach { free($0) }; free(cpath); free(ccwd) }
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        var m: Int32 = -1
        // forkpty: setsid + TIOCSCTTY in the child, so the shell owns the terminal and Ctrl-C reaches its job.
        // (posix_spawn cannot do TIOCSCTTY; zsh then had no controlling tty and ignored Ctrl-C.)
        let child = forkpty(&m, nil, nil, &size)
        if child == 0 {
            var none = sigset_t()
            sigemptyset(&none)
            sigprocmask(SIG_SETMASK, &none, nil)
            for sig: Int32 in 1..<32 { signal(sig, SIG_DFL) }
            let maxFD = getdtablesize()
            var fd: Int32 = 3
            while fd < maxFD { close(fd); fd += 1 }
            _ = chdir(ccwd)
            execve(cpath, argv, envp)
            _exit(127)
        }
        guard child > 0, m >= 0 else { return nil }
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
