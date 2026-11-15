import XCTest
@testable import AppHubCore

final class HashingTests: XCTestCase {
    func testSHA256KnownVectors() {
        XCTAssertEqual(
            SHA256.hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            SHA256.hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256.hex(Data("The quick brown fox jumps over the lazy dog".utf8)),
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        )
    }

    func testSHA256StreamingMatchesOneShot() {
        var hasher = SHA256()
        hasher.update(Data("The quick ".utf8))
        hasher.update(Data("brown fox jumps over the lazy dog".utf8))
        XCTAssertEqual(hasher.finalize(), SHA256.hash(Data("The quick brown fox jumps over the lazy dog".utf8)))
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testHexRoundTrip() {
        let data = Data([0x00, 0x0F, 0xA5, 0xFF])
        XCTAssertEqual(data.hexString, "000fa5ff")
        XCTAssertEqual(Data(hexString: "000FA5FF"), data)
        XCTAssertNil(Data(hexString: "abc"))
    }
}
