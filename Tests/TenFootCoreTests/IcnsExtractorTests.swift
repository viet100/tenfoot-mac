import Foundation
import Testing
@testable import TenFootCore

@Suite struct IcnsExtractorTests {
    private func be32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// "icns" + total length + a fake image element.
    private var icon: [UInt8] {
        let payload: [UInt8] = Array("ic07".utf8) + be32(12) + [1, 2, 3, 4]
        return Array("icns".utf8) + be32(8 + payload.count) + payload
    }

    /// A resource fork laid out like Finder writes one: header, data section
    /// (length-prefixed resource), then a map that also names the "icns" type.
    private func fork(with icon: [UInt8]) -> Data {
        let data = be32(icon.count) + icon
        let map = Array(repeating: UInt8(0), count: 28) + Array("icns".utf8) + be32(0x0000_0080)
        let dataOffset = 256
        let header = be32(dataOffset) + be32(dataOffset + data.count) + be32(data.count) + be32(map.count)
        let padding = Array(repeating: UInt8(0), count: dataOffset - header.count)
        return Data(header + padding + data + map)
    }

    @Test func findsTheIconInAResourceFork() {
        #expect(IcnsExtractor.icns(inResourceFork: fork(with: icon)) == Data(icon))
    }

    @Test func findsAnIconWithoutAHeader() {
        let blob = Data([9, 9, 9] + icon + [7, 7])
        #expect(IcnsExtractor.icns(inResourceFork: blob) == Data(icon))
    }

    @Test func nothingWhenThereIsNoIconOrItIsCutOff() {
        #expect(IcnsExtractor.icns(inResourceFork: Data()) == nil)
        #expect(IcnsExtractor.icns(inResourceFork: Data(Array("no icon here".utf8))) == nil)
        #expect(IcnsExtractor.icns(inResourceFork: Data(icon.dropLast(3))) == nil)
    }
}
