import Foundation

/// Finds the icon in a resource fork, which is where Finder keeps a custom icon set
/// with Get Info (pasting an image onto the icon).
///
/// A resource fork starts with a 16-byte header: where its data section begins, where
/// its map begins, and their lengths. The icon is stored in the data section as ordinary
/// `.icns` data, which begins with the bytes "icns" and its own total length.
public enum IcnsExtractor {
    public static func icns(inResourceFork fork: Data) -> Data? {
        let bytes = [UInt8](fork)
        var range = 0..<bytes.count
        // Search only the data section when the header makes sense, so the "icns"
        // type code listed in the map is never mistaken for icon data.
        if bytes.count >= 16 {
            let start = Int(bigEndian: bytes, at: 0)
            let length = Int(bigEndian: bytes, at: 8)
            if start >= 16, length > 0, start + length <= bytes.count {
                range = start..<(start + length)
            }
        }
        let magic: [UInt8] = Array("icns".utf8)
        var i = range.lowerBound
        while i + 8 <= range.upperBound {
            if Array(bytes[i..<i + 4]) == magic {
                let length = Int(bigEndian: bytes, at: i + 4)
                if length > 8, i + length <= range.upperBound {
                    return Data(bytes[i..<i + length])
                }
            }
            i += 1
        }
        return nil
    }
}

private extension Int {
    init(bigEndian bytes: [UInt8], at offset: Int) {
        self = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
    }
}
