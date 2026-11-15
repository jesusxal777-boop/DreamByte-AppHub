import Foundation

public enum CPUArchitecture: String, Codable, Sendable, CaseIterable, Equatable {
    case arm64
    case arm64e
    case arm64_32
    case armv7
    case armv7s
    case x86_64
    case i386
    case unknown

    public var displayName: String {
        switch self {
        case .arm64: "arm64"
        case .arm64e: "arm64e"
        case .arm64_32: "arm64_32"
        case .armv7: "armv7"
        case .armv7s: "armv7s"
        case .x86_64: "x86_64"
        case .i386: "i386"
        case .unknown: "unknown"
        }
    }

    public var isDeviceNative: Bool {
        self == .arm64 || self == .arm64e || self == .arm64_32
    }
}

public struct MachOInfo: Sendable, Equatable {
    public let architectures: [CPUArchitecture]
    public let isEncrypted: Bool
    public let isFat: Bool
    public let sliceCount: Int

    public init(architectures: [CPUArchitecture], isEncrypted: Bool, isFat: Bool, sliceCount: Int) {
        self.architectures = architectures
        self.isEncrypted = isEncrypted
        self.isFat = isFat
        self.sliceCount = sliceCount
    }
}

public enum MachOParser {
    /// Parses enough of a Mach-O header to answer the questions AppHub needs:
    /// which architectures are present, and whether the binary is FairPlay-encrypted.
    public static func parse(_ data: Data) -> MachOInfo? {
        let reader = ByteReader(data)
        guard reader.count >= 28 else { return nil }

        guard let firstBig = try? reader.bigEndianUInt32(at: 0) else { return nil }

        if firstBig == 0xcafebabe || firstBig == 0xcafebabf {
            return parseFat(reader: reader, is64: firstBig == 0xcafebabf)
        }

        guard let firstLittle = try? reader.uint32(at: 0) else { return nil }
        switch firstLittle {
        case 0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe:
            return parseThin(reader: reader, offset: 0)
        default:
            return nil
        }
    }

    private static func parseFat(reader: ByteReader, is64: Bool) -> MachOInfo? {
        guard let count = try? reader.bigEndianUInt32(at: 4) else { return nil }
        let sliceCount = Int(count)
        guard sliceCount > 0, sliceCount <= 64 else { return nil }

        let entrySize = is64 ? 32 : 20
        let tableStart = 8
        guard tableStart + sliceCount * entrySize <= reader.count else { return nil }

        var architectures: [CPUArchitecture] = []
        var encrypted = false

        for index in 0..<sliceCount {
            let entry = tableStart + index * entrySize
            guard let cpuType = try? reader.bigEndianUInt32(at: entry),
                  let cpuSubtype = try? reader.bigEndianUInt32(at: entry + 4) else {
                continue
            }
            let offset: Int
            if is64 {
                guard let raw = try? reader.bigEndianUInt64(at: entry + 8) else { continue }
                offset = Int(raw)
            } else {
                guard let raw = try? reader.bigEndianUInt32(at: entry + 8) else { continue }
                offset = Int(raw)
            }
            let architecture = classify(cpuType: cpuType, cpuSubtype: cpuSubtype)
            if !architectures.contains(architecture) {
                architectures.append(architecture)
            }
            if let slice = parseThin(reader: reader, offset: offset),
               slice.isEncrypted {
                encrypted = true
            }
        }

        return MachOInfo(
            architectures: architectures,
            isEncrypted: encrypted,
            isFat: true,
            sliceCount: sliceCount
        )
    }

    private static func parseThin(reader: ByteReader, offset: Int) -> MachOInfo? {
        guard offset >= 0, offset + 28 <= reader.count else { return nil }

        guard let littleMagic = try? reader.uint32(at: offset) else { return nil }
        let littleEndian: Bool
        let resolved64: Bool
        switch littleMagic {
        case 0xfeedfacf:
            littleEndian = true
            resolved64 = true
        case 0xfeedface:
            littleEndian = true
            resolved64 = false
        case 0xcffaedfe:
            littleEndian = false
            resolved64 = true
        case 0xcefaedfe:
            littleEndian = false
            resolved64 = false
        default:
            return nil
        }

        let read32: (Int) -> UInt32? = { position in
            littleEndian
                ? (try? reader.uint32(at: position))
                : (try? reader.bigEndianUInt32(at: position))
        }

        guard let cpuType = read32(offset + 4),
              let cpuSubtype = read32(offset + 8),
              let commandCount = read32(offset + 16),
              let commandBytes = read32(offset + 20) else {
            return nil
        }

        let headerSize = resolved64 ? 32 : 28
        let commandsStart = offset + headerSize
        let available = reader.count - commandsStart
        let boundedBytes = min(Int(commandBytes), max(0, available))
        let end = commandsStart + boundedBytes

        var encrypted = false
        var cursor = commandsStart
        let maxCommands = min(Int(commandCount), 16_384)

        for _ in 0..<maxCommands {
            guard cursor + 8 <= end, cursor + 8 <= reader.count else { break }
            guard let command = read32(cursor),
                  let size = read32(cursor + 4) else { break }
            let commandSize = Int(size)
            guard commandSize >= 8, cursor + commandSize <= reader.count else { break }

            if command == 0x21 || command == 0x2c {
                if let cryptid = read32(cursor + 16), cryptid != 0 {
                    encrypted = true
                }
            }
            cursor += commandSize
        }

        let architecture = classify(cpuType: cpuType, cpuSubtype: cpuSubtype)
        return MachOInfo(
            architectures: [architecture],
            isEncrypted: encrypted,
            isFat: false,
            sliceCount: 1
        )
    }

    private static func classify(cpuType: UInt32, cpuSubtype: UInt32) -> CPUArchitecture {
        let subtype = cpuSubtype & 0x00FF_FFFF
        switch cpuType {
        case 0x0100_000C:
            return subtype == 2 ? .arm64e : .arm64
        case 0x0200_000C:
            return .arm64_32
        case 12:
            return subtype == 11 ? .armv7s : .armv7
        case 0x0100_0007:
            return .x86_64
        case 7:
            return .i386
        default:
            return .unknown
        }
    }
}
