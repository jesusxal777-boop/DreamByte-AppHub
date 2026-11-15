import Foundation

/// Bounds-checked reader over `Data`. All offsets are relative to the data start,
/// which keeps slicing bugs out of the archive and Mach-O parsers.
public struct ByteReader: Sendable {
    public let data: Data

    public init(_ data: Data) {
        self.data = data
    }

    public var count: Int { data.count }

    public func byte(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < data.count else {
            throw AppHubError(.invalidArchive, "Read out of bounds at offset \(offset).")
        }
        return data[data.startIndex + offset]
    }

    public func uint16(at offset: Int) throws -> UInt16 {
        UInt16(try byte(at: offset)) | (UInt16(try byte(at: offset + 1)) << 8)
    }

    public func uint32(at offset: Int) throws -> UInt32 {
        UInt32(try byte(at: offset))
            | (UInt32(try byte(at: offset + 1)) << 8)
            | (UInt32(try byte(at: offset + 2)) << 16)
            | (UInt32(try byte(at: offset + 3)) << 24)
    }

    public func uint64(at offset: Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(try byte(at: offset + index)) << UInt64(index * 8)
        }
        return value
    }

    public func bigEndianUInt32(at offset: Int) throws -> UInt32 {
        (UInt32(try byte(at: offset)) << 24)
            | (UInt32(try byte(at: offset + 1)) << 16)
            | (UInt32(try byte(at: offset + 2)) << 8)
            | UInt32(try byte(at: offset + 3))
    }

    public func bigEndianUInt16(at offset: Int) throws -> UInt16 {
        (UInt16(try byte(at: offset)) << 8) | UInt16(try byte(at: offset + 1))
    }

    public func bigEndianUInt64(at offset: Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(try byte(at: offset + index))
        }
        return value
    }

    public func bytes(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw AppHubError(.invalidArchive, "Byte range \(offset)..<\(offset + count) is out of bounds.")
        }
        let start = data.startIndex + offset
        return data[start..<(start + count)]
    }

    public func string(at offset: Int, count: Int) throws -> String {
        let raw = try bytes(at: offset, count: count)
        return String(data: raw, encoding: .utf8) ?? String(decoding: raw, as: UTF8.self)
    }
}

public extension Data {
    func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return (UInt32(self[startIndex + offset]) << 24)
            | (UInt32(self[startIndex + offset + 1]) << 16)
            | (UInt32(self[startIndex + offset + 2]) << 8)
            | UInt32(self[startIndex + offset + 3])
    }
}
