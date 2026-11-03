import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Thin POSIX wrapper shared by the CLI (client) and the app (server).
public enum UnixSocket {
    public enum SocketError: Error, Equatable {
        case pathTooLong, socket(Int32), connect(Int32), bind(Int32), listen(Int32), write(Int32), timeout, closed
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < cap else { throw SocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    private static func setTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Connects to a listening socket. Fails fast when the app is not running (no file / refused).
    public static func connect(path: String, timeout: TimeInterval) throws -> Int32 {
        var addr = try address(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.socket(errno) }
        setTimeout(fd, timeout)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard r == 0 else { let e = errno; close(fd); throw SocketError.connect(e) }
        return fd
    }

    public static func write(_ fd: Int32, _ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, data.count - offset) }
            if n < 0 {
                if errno == EINTR { continue }
                throw errno == EAGAIN ? SocketError.timeout : SocketError.write(errno)
            }
            offset += n
        }
    }

    /// Reads until a newline (exclusive). Honors the socket's receive timeout.
    public static func readLine(_ fd: Int32, maxBytes: Int = Bridge.maxMessageBytes) throws -> Data {
        var out = Data()
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n == 0 { throw SocketError.closed }
            if n < 0 {
                if errno == EINTR { continue }
                throw errno == EAGAIN ? SocketError.timeout : SocketError.closed
            }
            if byte == 0x0A { return out }
            out.append(byte)
            if out.count > maxBytes { throw SocketError.closed }
        }
    }

    /// Creates the listening socket with mode 0600 inside a 0700 directory (PRD §2.8).
    public static func listen(path: String) throws -> Int32 {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        unlink(path)
        var addr = try address(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.socket(errno) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        // umask makes the socket file 0600 from the moment it exists.
        let old = umask(0o177)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(old)
        guard r == 0 else { let e = errno; close(fd); throw SocketError.bind(e) }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else { let e = errno; close(fd); throw SocketError.listen(e) }
        return fd
    }

    /// True when the peer runs as the same user (defence in depth on top of the 0600 file mode).
    public static func peerIsSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    public static func setTimeouts(_ fd: Int32, _ seconds: TimeInterval) { setTimeout(fd, seconds) }

    /// Receive timeout only (0 = block); sends keep their timeout so a peer that stops reading cannot hang the writer.
    public static func setReceiveTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }
}
