import Foundation

/// Minimal ASN.1 DER reader — enough for X.509 summaries, no dependencies.
public struct ASN1Node: Sendable {
    public let tag: UInt8
    public let content: Data
    public let encoded: Data

    public var children: [ASN1Node] {
        var result: [ASN1Node] = []
        var offset = 0
        while offset < content.count {
            guard let node = ASN1Node.parse(content, offset: &offset) else { break }
            result.append(node)
        }
        return result
    }

    public static func parse(_ data: Data, offset: inout Int) -> ASN1Node? {
        guard offset + 2 <= data.count else { return nil }
        let start = offset
        let tag = data[data.startIndex + offset]
        offset += 1
        guard let lengthByte = byte(data, offset) else { return nil }
        offset += 1

        var length = Int(lengthByte)
        if lengthByte & 0x80 != 0 {
            let byteCount = Int(lengthByte & 0x7F)
            guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else { return nil }
            length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(data[data.startIndex + offset])
                offset += 1
            }
        }
        guard length >= 0, offset + length <= data.count else { return nil }
        let contentStart = data.startIndex + offset
        let content = data[contentStart..<(contentStart + length)]
        offset += length
        let encoded = data[data.startIndex + start..<(data.startIndex + offset)]
        return ASN1Node(tag: tag, content: Data(content), encoded: Data(encoded))
    }

    public static func parse(_ data: Data) -> ASN1Node? {
        var offset = 0
        return parse(data, offset: &offset)
    }

    private static func byte(_ data: Data, _ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }
}

public struct X509CertificateSummary: Codable, Sendable, Equatable {
    public let commonName: String?
    public let issuerCommonName: String?
    public let serialNumber: String?
    public let notBefore: Date?
    public let notAfter: Date?
    public let sha256Fingerprint: String

    public func isExpired(at date: Date = Date()) -> Bool {
        guard let notAfter else { return false }
        return notAfter < date
    }

    public static func parse(der data: Data) -> X509CertificateSummary? {
        guard let root = ASN1Node.parse(data), root.tag == 0x30 else { return nil }
        let parts = root.children
        guard parts.count >= 1 else { return nil }
        let tbs = parts[0]
        guard tbs.tag == 0x30 else { return nil }
        var fields = tbs.children

        if let first = fields.first, first.tag == 0xA0 {
            fields.removeFirst()
        }
        guard fields.count >= 6 else { return nil }

        let serial = fields[0]
        let issuer = fields[2]
        let validity = fields[3]
        let subject = fields[4]

        var notBefore: Date?
        var notAfter: Date?
        let validityFields = validity.children
        if validityFields.count >= 2 {
            notBefore = parseTime(validityFields[0])
            notAfter = parseTime(validityFields[1])
        }

        return X509CertificateSummary(
            commonName: commonName(in: subject),
            issuerCommonName: commonName(in: issuer),
            serialNumber: serial.content.hexString,
            notBefore: notBefore,
            notAfter: notAfter,
            sha256Fingerprint: SHA256.hex(data)
        )
    }

    private static func commonName(in name: ASN1Node) -> String? {
        for set in name.children {
            for attribute in set.children {
                let parts = attribute.children
                guard parts.count >= 2 else { continue }
                let oid = parts[0]
                if oid.tag == 0x06, oid.content == Data([0x55, 0x04, 0x03]) {
                    return String(decoding: parts[1].content, as: UTF8.self)
                }
            }
        }
        return nil
    }

    private static func parseTime(_ node: ASN1Node) -> Date? {
        let text = String(decoding: node.content, as: UTF8.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        if node.tag == 0x17 { // UTCTime
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            if let date = formatter.date(from: text) {
                let year = Calendar(identifier: .gregorian).component(.year, from: date)
                if year >= 2000 { return date }
                var components = DateComponents()
                components.year = year + 100
                components.month = Calendar(identifier: .gregorian).component(.month, from: date)
                components.day = Calendar(identifier: .gregorian).component(.day, from: date)
                components.hour = Calendar(identifier: .gregorian).component(.hour, from: date)
                components.minute = Calendar(identifier: .gregorian).component(.minute, from: date)
                components.second = Calendar(identifier: .gregorian).component(.second, from: date)
                return Calendar(identifier: .gregorian).date(from: components)
            }
        } else if node.tag == 0x18 { // GeneralizedTime
            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
            return formatter.date(from: text)
        }
        return nil
    }
}
