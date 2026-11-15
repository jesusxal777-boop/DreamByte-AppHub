import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// Minimal blocking HTTP/1.1 server used to exercise the real download path in
/// tests. It serves one static body on every request and ignores the request
/// line beyond reading it.
final class LocalHTTPServer: @unchecked Sendable {
    let port: UInt16
    private let listenFD: Int32
    private let body: Data
    private let lock = NSLock()
    private var running = true

    init(body: Data) throws {
        self.body = body
        #if canImport(Glibc)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif
        let fd = socket(AF_INET, socketType, 0)
        guard fd >= 0 else { throw FixtureServerError.socket }
        self.listenFD = fd

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        #if canImport(Glibc)
        address.sin_family = sa_family_t(AF_INET)
        #else
        address.sin_family = sa_family_t(AF_INET)
        #endif
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw FixtureServerError.bind
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            close(fd)
            throw FixtureServerError.bind
        }
        self.port = UInt16(bigEndian: actual.sin_port)
    }

    var baseURL: String { "http://127.0.0.1:\(port)/" }

    func start() {
        let fd = listenFD
        Thread.detachNewThread { [self] in
            while isRunning {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { break }
                serve(client)
                close(client)
            }
        }
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        shutdown(listenFD, Int32(SHUT_RDWR))
        close(listenFD)
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func serve(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        buffer.withUnsafeMutableBytes { raw in
            _ = recv(client, raw.baseAddress, raw.count, 0)
        }

        var response = Data("HTTP/1.1 200 OK\r\n".utf8)
        response.append(Data("Content-Type: application/octet-stream\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)

        response.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = send(client, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if written <= 0 { break }
                offset += written
            }
        }
    }
}

enum FixtureServerError: Error {
    case socket
    case bind
}
