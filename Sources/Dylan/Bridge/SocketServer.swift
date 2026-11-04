import DylanCore
import Foundation

/// Unix socket server for the `dylan` CLI. PRD §2.6 / §2.8.
/// Reads happen on a background queue; every message is handled on the main actor.
/// Dylan never executes anything it receives here.
final class SocketServer {
    static let shared = SocketServer()
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "dylan.socket", attributes: .concurrent)

    func start() {
        guard listenFD < 0 else { return }
        do {
            listenFD = try UnixSocket.listen(path: Bridge.socketURL.path)
        } catch {
            AppModel.shared.lastError = "Socket: \(error)"
            return
        }
        let fd = listenFD
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        // @Sendable: runs on the socket queue. A main-actor closure here traps at runtime (Swift 6 isolation checks).
        s.setEventHandler { @Sendable in SocketServer.acceptOne(fd) }
        s.resume()
        source = s
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 { close(listenFD); unlink(Bridge.socketURL.path) }
        listenFD = -1
    }

    nonisolated private static func acceptOne(_ listenFD: Int32) {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        guard UnixSocket.peerIsSameUser(fd) else { close(fd); return }
        // Long enough for a permission card (30 s default + margin); stuck clients are dropped.
        UnixSocket.setTimeouts(fd, 120)
        let conn = Connection(fd: fd)
        DispatchQueue.global(qos: .userInitiated).async { conn.readLoop() }
    }
}

/// One client. `reply` may be called later from the main actor (permission answers),
/// so writes and close share a lock and a closed connection silently drops replies.
nonisolated final class Connection: @unchecked Sendable {
    let id = UUID()
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    init(fd: Int32) { self.fd = fd }

    func readLoop() {
        var buffer = LineBuffer()
        var chunk = [UInt8](repeating: 0, count: 8192)
        defer { shutdown() }
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { if n < 0 && errno == EINTR { continue }; return }
            guard let lines = try? buffer.append(Data(chunk[0..<n])) else { return }   // > 64 KB: drop the client
            for line in lines {
                guard let msg = try? BridgeMessage.decode(line: line) else { continue }
                let waitsForReply: Bool
                switch msg { case .permissionAsk, .ping, .debugState: waitsForReply = true; default: waitsForReply = false }
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        AppModel.shared.handle(msg, connection: self.id) { data in self.write(data) }
                    }
                    done.signal()
                }
                // Keep order of messages on one connection.
                if !waitsForReply { done.wait() }
            }
        }
    }

    func write(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        try? UnixSocket.write(fd, data)
    }

    private func shutdown() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        close(fd)
        let id = self.id
        DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.connectionClosed(id) } }
    }
}
