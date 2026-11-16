import AppKit
import SwiftUI
import TenFootCore

/// A library entry ready to show: its icon and the two colours taken from it
/// (used for the tile background, the selector tint and the backdrop).
struct Game: Identifiable {
    let id: UUID
    let title: String
    let url: URL
    let icon: NSImage
    let primary: Color
    let secondary: Color

    init(entry: LibraryEntry) {
        id = entry.id
        title = entry.title
        url = URL(fileURLWithPath: entry.path)
        icon = NSWorkspace.shared.icon(forFile: entry.path)
        (primary, secondary) = Self.colors(of: icon)
    }

    /// The name to show for an app or executable: "Hollow Knight.app" becomes "Hollow Knight".
    static func title(for url: URL) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }

    /// Average colour of the top and bottom halves of the icon.
    private static func colors(of image: NSImage) -> (Color, Color) {
        let side = 8
        var rect = NSRect(x: 0, y: 0, width: 128, height: 128)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (.gray, .black) }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return (.gray, .black) }

        func average(rows: Range<Int>) -> Color {
            var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
            for y in rows {
                for x in 0..<side {
                    let i = (y * side + x) * 4
                    red += Double(data[i])
                    green += Double(data[i + 1])
                    blue += Double(data[i + 2])
                    alpha += Double(data[i + 3])
                }
            }
            guard alpha > 0 else { return .gray }
            // Premultiplied: dividing by total alpha gives the average visible colour.
            return Color(.sRGB, red: red / alpha, green: green / alpha, blue: blue / alpha)
        }
        return (average(rows: 0..<side / 2), average(rows: side / 2..<side))
    }
}

enum LibraryLocation {
    /// ~/Library/Application Support/TenFoot/library.json
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TenFoot", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}
