import Foundation

/// Runs a short command synchronously (callers stay off the main thread).
public enum Shell {
    /// stdout as text, or nil on launch failure or timeout. The pipe is drained while the child runs,
    /// so output larger than the pipe buffer (~64 KB) cannot stall it.
    // shortcut: blocks the calling thread (a cooperative-pool thread under Task.detached) up to `timeout`;
    // move to an async Process wrapper if many long commands run at once.
    /// `cwd` sets the working directory; `requireSuccess` also returns nil on a non-zero exit status.
    public static func run(_ path: String, _ args: [String], timeout: TimeInterval = 5, cwd: String? = nil, requireSuccess: Bool = false) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let reader = out.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { box.data = reader.readDataToEndOfFile(); done.signal() }
        guard done.wait(timeout: .now() + timeout) == .success else { p.terminate(); return nil }
        p.waitUntilExit()
        if requireSuccess && p.terminationStatus != 0 { return nil }
        return String(data: box.data, encoding: .utf8)
    }

    private final class Box: @unchecked Sendable { var data = Data() }   // written once, read after the semaphore
}
