import CZlib
import Foundation

public struct ZipLimits: Sendable {
    public var maxEntries: Int
    public var maxCentralDirectorySize: Int
    public var maxMetadataSize: Int
    public var maxCompressionRatio: Double

    public init(
        maxEntries: Int = 100_000,
        maxCentralDirectorySize: Int = 64 << 20,
        maxMetadataSize: Int = 32 << 20,
        maxCompressionRatio: Double = 2_000
    ) {
        self.maxEntries = maxEntries
        self.maxCentralDirectorySize = maxCentralDirectorySize
        self.maxMetadataSize = maxMetadataSize
        self.maxCompressionRatio = maxCompressionRatio
    }

    public static let `default` = ZipLimits()
}

public struct ZipEntry: Sendable, Equatable {
    public let name: String
    public let compressionMethod: UInt16
    public let flags: UInt16
    public let crc32: UInt32
    public let compressedSize: Int
    public let uncompressedSize: Int
    public let localHeaderOffset: Int

    public var isDirectory: Bool { name.hasSuffix("/") }
    public var isEncrypted: Bool { (flags & 0x0001) != 0 }
}

/// Minimal, hardened ZIP reader. Only the central directory and selected
/// metadata entries are ever read; nothing is extracted to disk implicitly.
public final class ZipArchive {
    public let url: URL
    public let entries: [ZipEntry]
    private let reader: ByteReader
    private let limits: ZipLimits

    public init(url: URL, limits: ZipLimits = .default) throws {
        self.url = url
        self.limits = limits

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw AppHubError.fileRead("Could not open archive: \(error.localizedDescription)")
        }
        guard data.count >= 22 else {
            throw AppHubError.invalidArchive("File is too small to be a ZIP archive.")
        }
        self.reader = ByteReader(data)

        let directory = try Self.readCentralDirectory(reader: reader, limits: limits)
        self.entries = directory.entries
    }

    public func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    public func entries(withPrefix prefix: String) -> [ZipEntry] {
        entries.filter { $0.name.hasPrefix(prefix) }
    }

    public func contains(_ name: String) -> Bool {
        entry(named: name) != nil
    }

    /// Reads and validates one entry. CRC-32 is always verified.
    public func data(for entry: ZipEntry, maxSize: Int? = nil) throws -> Data {
        let cap = min(maxSize ?? limits.maxMetadataSize, limits.maxMetadataSize)
        guard entry.uncompressedSize >= 0, entry.uncompressedSize <= cap else {
            throw AppHubError(.entryTooLarge, "Entry \(entry.name) exceeds the metadata size limit.")
        }
        if entry.isEncrypted {
            throw AppHubError(.encryptedArchive, "Entry \(entry.name) is encrypted.")
        }
        if entry.isDirectory {
            return Data()
        }

        let localOffset = entry.localHeaderOffset
        guard let signature = try? reader.uint32(at: localOffset), signature == 0x04034b50 else {
            throw AppHubError.invalidArchive("Invalid local header for \(entry.name).")
        }
        let nameLength = Int(try reader.uint16(at: localOffset + 26))
        let extraLength = Int(try reader.uint16(at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        guard dataStart >= 0,
              entry.compressedSize >= 0,
              dataStart <= reader.count,
              entry.compressedSize <= reader.count - dataStart else {
            throw AppHubError.invalidArchive("Compressed data for \(entry.name) is out of bounds.")
        }

        if entry.compressedSize > 0 {
            let ratio = Double(entry.uncompressedSize) / Double(entry.compressedSize)
            guard ratio <= limits.maxCompressionRatio else {
                throw AppHubError(.archiveTooLarge, "Suspicious compression ratio for \(entry.name).")
            }
        }

        let compressed = try reader.bytes(at: dataStart, count: entry.compressedSize)
        let output: Data
        switch entry.compressionMethod {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else {
                throw AppHubError.invalidArchive("Stored entry \(entry.name) has inconsistent sizes.")
            }
            output = compressed
        case 8:
            output = try inflate(compressed, expectedSize: entry.uncompressedSize, name: entry.name)
        default:
            throw AppHubError(.unsupportedCompression, "Unsupported compression method \(entry.compressionMethod) for \(entry.name).")
        }

        guard CRC32.checksum(output) == entry.crc32 else {
            throw AppHubError(.checksumMismatch, "CRC mismatch for \(entry.name).")
        }
        return output
    }

    private func inflate(_ compressed: Data, expectedSize: Int, name: String) throws -> Data {
        if expectedSize == 0 {
            return Data()
        }
        var output = [UInt8](repeating: 0, count: expectedSize)
        var written = 0
        let status: Int32 = compressed.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                apphub_inflate_raw(
                    source.bindMemory(to: UInt8.self).baseAddress,
                    compressed.count,
                    destination.bindMemory(to: UInt8.self).baseAddress,
                    expectedSize,
                    &written
                )
            }
        }
        switch status {
        case 0:
            break
        case -3:
            throw AppHubError.invalidArchive("Entry \(name) expands beyond its declared size.")
        default:
            throw AppHubError.invalidArchive("Could not inflate \(name) (zlib \(status)).")
        }
        guard written == expectedSize else {
            throw AppHubError.invalidArchive("Entry \(name) produced \(written) of \(expectedSize) bytes.")
        }
        return Data(output)
    }

    // MARK: - Central directory

    private struct Directory {
        let entries: [ZipEntry]
    }

    private static func readCentralDirectory(reader: ByteReader, limits: ZipLimits) throws -> Directory {
        guard let eocdOffset = findEndOfCentralDirectory(reader: reader) else {
            throw AppHubError.invalidArchive("End of central directory not found.")
        }

        var totalEntries = Int(try reader.uint16(at: eocdOffset + 10))
        var directorySize = Int(try reader.uint32(at: eocdOffset + 12))
        var directoryOffset = Int(try reader.uint32(at: eocdOffset + 16))

        if totalEntries == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let zip64 = try readZip64End(reader: reader, eocdOffset: eocdOffset)
            totalEntries = zip64.entries
            directorySize = zip64.size
            directoryOffset = zip64.offset
        }

        guard totalEntries >= 0, totalEntries <= limits.maxEntries else {
            throw AppHubError(.archiveTooLarge, "Archive declares too many entries.")
        }
        guard directorySize >= 0, directorySize <= limits.maxCentralDirectorySize else {
            throw AppHubError(.archiveTooLarge, "Central directory is too large.")
        }
        guard directoryOffset >= 0,
              directorySize <= reader.count,
              directoryOffset <= reader.count - directorySize else {
            throw AppHubError.invalidArchive("Central directory is out of bounds.")
        }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(totalEntries)
        var offset = directoryOffset

        for _ in 0..<totalEntries {
            guard offset + 46 <= reader.count else {
                throw AppHubError.invalidArchive("Truncated central directory entry.")
            }
            guard try reader.uint32(at: offset) == 0x02014b50 else {
                throw AppHubError.invalidArchive("Invalid central directory signature.")
            }
            let flags = try reader.uint16(at: offset + 8)
            let method = try reader.uint16(at: offset + 10)
            let crc = try reader.uint32(at: offset + 16)
            var compressed = Int(try reader.uint32(at: offset + 20))
            var uncompressed = Int(try reader.uint32(at: offset + 24))
            let nameLength = Int(try reader.uint16(at: offset + 28))
            let extraLength = Int(try reader.uint16(at: offset + 30))
            let commentLength = Int(try reader.uint16(at: offset + 32))
            var localOffset = Int(try reader.uint32(at: offset + 42))

            let nameStart = offset + 46
            guard nameLength >= 0, nameLength <= reader.count - nameStart else {
                throw AppHubError.invalidArchive("Invalid entry name length.")
            }
            let rawName = try reader.bytes(at: nameStart, count: nameLength)
            let name: String
            if (flags & 0x0800) != 0 {
                name = String(decoding: rawName, as: UTF8.self)
            } else {
                name = String(data: rawName, encoding: .isoLatin1)
                    ?? String(decoding: rawName, as: UTF8.self)
            }

            guard isSafePath(name) else {
                throw AppHubError(.unsafePath, "Archive contains an unsafe path: \(name)")
            }

            let extraStart = nameStart + nameLength
            guard extraLength >= 0, extraLength <= reader.count - extraStart else {
                throw AppHubError.invalidArchive("Invalid extra field length.")
            }
            let extra = try reader.bytes(at: extraStart, count: extraLength)
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                let zip64 = try parseZip64Extra(extra)
                compressed = zip64.compressed ?? compressed
                uncompressed = zip64.uncompressed ?? uncompressed
                localOffset = zip64.localOffset ?? localOffset
            }

            entries.append(
                ZipEntry(
                    name: name,
                    compressionMethod: method,
                    flags: flags,
                    crc32: crc,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: localOffset
                )
            )

            offset = extraStart + extraLength + commentLength
        }

        return Directory(entries: entries)
    }

    private static func findEndOfCentralDirectory(reader: ByteReader) -> Int? {
        let minimum = 22
        guard reader.count >= minimum else { return nil }
        let earliest = max(0, reader.count - 65_557)
        var offset = reader.count - minimum
        while offset >= earliest {
            if let signature = try? reader.uint32(at: offset), signature == 0x06054b50 {
                if let commentLength = try? reader.uint16(at: offset + 20),
                   offset + minimum + Int(commentLength) <= reader.count {
                    return offset
                }
            }
            offset -= 1
        }
        return nil
    }

    private static func readZip64End(
        reader: ByteReader,
        eocdOffset: Int
    ) throws -> (entries: Int, size: Int, offset: Int) {
        let locatorOffset = eocdOffset - 20
        guard locatorOffset >= 0,
              (try? reader.uint32(at: locatorOffset)) == 0x07064b50 else {
            throw AppHubError.invalidArchive("ZIP64 locator missing.")
        }
        let zip64Offset = Int(try reader.uint64(at: locatorOffset + 8))
        guard zip64Offset >= 0, zip64Offset + 56 <= reader.count,
              try reader.uint32(at: zip64Offset) == 0x06064b50 else {
            throw AppHubError.invalidArchive("Invalid ZIP64 end record.")
        }
        let entries = Int(try reader.uint64(at: zip64Offset + 32))
        let size = Int(try reader.uint64(at: zip64Offset + 40))
        let offset = Int(try reader.uint64(at: zip64Offset + 48))
        return (entries, size, offset)
    }

    private static func parseZip64Extra(_ extra: Data) throws -> (
        uncompressed: Int?, compressed: Int?, localOffset: Int?, disk: Int?
    ) {
        let reader = ByteReader(extra)
        var offset = 0
        while offset + 4 <= reader.count {
            let headerID = try reader.uint16(at: offset)
            let size = Int(try reader.uint16(at: offset + 2))
            let body = offset + 4
            guard size >= 0, size <= reader.count - body else { break }
            if headerID == 0x0001 {
                var cursor = body
                var uncompressed: Int?
                var compressed: Int?
                var localOffset: Int?
                var disk: Int?
                if cursor + 8 <= body + size {
                    uncompressed = Int(try reader.uint64(at: cursor)); cursor += 8
                }
                if cursor + 8 <= body + size {
                    compressed = Int(try reader.uint64(at: cursor)); cursor += 8
                }
                if cursor + 8 <= body + size {
                    localOffset = Int(try reader.uint64(at: cursor)); cursor += 8
                }
                if cursor + 4 <= body + size {
                    disk = Int(try reader.uint32(at: cursor))
                }
                return (uncompressed, compressed, localOffset, disk)
            }
            offset = body + size
        }
        return (nil, nil, nil, nil)
    }

    private static func isSafePath(_ name: String) -> Bool {
        guard !name.isEmpty, !name.contains("\0"), !name.contains("\\") else { return false }
        guard !name.hasPrefix("/"), !name.hasPrefix("~") else { return false }
        if name.count >= 2, name[name.index(name.startIndex, offsetBy: 1)] == ":" {
            return false
        }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        for component in components where component == "." || component == ".." {
            return false
        }
        return true
    }
}
