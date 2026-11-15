import Foundation

// MARK: - CRC-32 (IEEE 802.3, used by ZIP)

public enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    public static func checksum(bytes: UnsafeRawBufferPointer, count: Int) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let base = bytes.bindMemory(to: UInt8.self)
        for index in 0..<count {
            crc = table[Int((crc ^ UInt32(base[index])) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - SHA-256 (FIPS 180-4)

public struct SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private var buffer: [UInt8] = []
    private var totalBytes: UInt64 = 0

    public init() {}

    public mutating func update(_ data: Data) {
        update(bytes: [UInt8](data))
    }

    public mutating func update(bytes: [UInt8]) {
        totalBytes += UInt64(bytes.count)
        buffer.append(contentsOf: bytes)
        var offset = 0
        while buffer.count - offset >= 64 {
            process(Array(buffer[offset..<(offset + 64)]))
            offset += 64
        }
        if offset > 0 {
            buffer.removeFirst(offset)
        }
    }

    public mutating func finalize() -> Data {
        let bitLength = totalBytes * 8
        buffer.append(0x80)
        while buffer.count % 64 != 56 {
            buffer.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            buffer.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        var offset = 0
        while offset < buffer.count {
            process(Array(buffer[offset..<(offset + 64)]))
            offset += 64
        }
        buffer.removeAll()
        var digest = Data()
        for word in state {
            digest.append(UInt8((word >> 24) & 0xFF))
            digest.append(UInt8((word >> 16) & 0xFF))
            digest.append(UInt8((word >> 8) & 0xFF))
            digest.append(UInt8(word & 0xFF))
        }
        return digest
    }

    public static func hash(_ data: Data) -> Data {
        var hasher = SHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    public static func hex(_ data: Data) -> String {
        hash(data).map { String(format: "%02x", $0) }.joined()
    }

    private mutating func process(_ block: [UInt8]) {
        var w = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let base = index * 4
            w[index] = (UInt32(block[base]) << 24)
                | (UInt32(block[base + 1]) << 16)
                | (UInt32(block[base + 2]) << 8)
                | UInt32(block[base + 3])
        }
        for index in 16..<64 {
            let s0 = rotate(w[index - 15], 7) ^ rotate(w[index - 15], 18) ^ (w[index - 15] >> 3)
            let s1 = rotate(w[index - 2], 17) ^ rotate(w[index - 2], 19) ^ (w[index - 2] >> 10)
            w[index] = w[index - 16] &+ s0 &+ w[index - 7] &+ s1
        }

        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]

        for index in 0..<64 {
            let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let temp1 = h &+ s1 &+ ch &+ Self.k[index] &+ w[index]
            let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj
            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        state[0] = state[0] &+ a
        state[1] = state[1] &+ b
        state[2] = state[2] &+ c
        state[3] = state[3] &+ d
        state[4] = state[4] &+ e
        state[5] = state[5] &+ f
        state[6] = state[6] &+ g
        state[7] = state[7] &+ h
    }

    private func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

// MARK: - Hex helpers

public extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let cleaned = hexString.filter { !$0.isWhitespace }
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
