import CryptoKit
import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct PortableSHA256Tests {
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    @Test func knownVectors() {
        #expect(hex(PortableSHA256.hash(Data())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(hex(PortableSHA256.hash(Data("abc".utf8))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func matchesCryptoKitAcrossBlockBoundaries() {
        for length in [1, 55, 56, 63, 64, 65, 119, 120, 1000] {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
            #expect(PortableSHA256.hash(data) == Array(SHA256.hash(data: data)), "length \(length)")
        }
    }
}
