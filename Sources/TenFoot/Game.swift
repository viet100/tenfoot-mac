import AppKit
import SwiftUI
import TenFootCore

/// A library entry ready to show: its icon and the colours taken from it
/// (used for the selector tint and the backdrop).
struct Game: Identifiable {
    let id: UUID
    let title: String
    let url: URL
    let icon: NSImage
    /// Four colours from the icon, strongest first: the backdrop's gradient, and the
    /// first one tints the selector.
    let palette: [Color]
    var primary: Color { palette[0] }

    init(entry: LibraryEntry, iconStyle: IconStyle) {
        id = entry.id
        title = entry.title
        url = URL(fileURLWithPath: entry.path)
        switch iconStyle {
        case .matchMacOS:
            icon = NSWorkspace.shared.icon(forFile: entry.path)
        case .fullColour:
            icon = Self.customIcon(at: url) ?? Self.bundleIcon(at: url) ?? NSWorkspace.shared.icon(forFile: entry.path)
        }
        palette = Self.palette(of: icon)
    }

    /// A custom icon set in Finder with Get Info, exactly as it was pasted in. Finder keeps
    /// it in a resource fork: the file's own for a plain file (such as an .exe), or the
    /// hidden "Icon\r" file's inside an app or folder.
    private static func customIcon(at url: URL) -> NSImage? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let holder = isDirectory.boolValue ? url.appendingPathComponent("Icon\r") : url
        let fork = URL(fileURLWithPath: holder.path + "/..namedfork/rsrc")
        guard let data = try? Data(contentsOf: fork), !data.isEmpty,
              let icns = IcnsExtractor.icns(inResourceFork: data) else { return nil }
        return NSImage(data: icns)
    }

    /// The app's own icon file from inside its bundle (Contents/Resources/<name>.icns).
    /// It's the full-colour artwork, untouched by the macOS icon style. Apps that only
    /// ship their icon in an asset catalog have no such file, so this returns nil.
    private static func bundleIcon(at url: URL) -> NSImage? {
        guard let bundle = Bundle(url: url) else { return nil }
        let names = ["CFBundleIconFile", "CFBundleIconName"].compactMap {
            bundle.object(forInfoDictionaryKey: $0) as? String
        }
        for name in names {
            let file = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
            if let iconURL = bundle.url(forResource: file, withExtension: nil),
               let image = NSImage(contentsOf: iconURL) {
                return image
            }
        }
        return nil
    }

    /// The name to show for an app or executable: "Hollow Knight.app" becomes "Hollow Knight".
    static func title(for url: URL) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }

    /// Four colours picked out of the icon, strongest first. An icon with fewer clear
    /// colours repeats them in darker shades, so the backdrop still has some range.
    private static func palette(of image: NSImage) -> [Color] {
        let picked = IconPalette.colors(rgba: pixels(of: image), count: 4)
        guard !picked.isEmpty else { return [.gray, .black, .gray, .black] }
        return (0..<4).map { i in
            let rgb = picked[i % picked.count]
            let color = Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
            let round = i / picked.count // 0 the first time round, then darker
            return round == 0 ? color : color.mix(with: .black, by: 0.3 * Double(round))
        }
    }

    /// The icon drawn small (16 × 16), as RGBA bytes with the alpha taken back out.
    private static func pixels(of image: NSImage) -> [UInt8] {
        let side = 16
        var rect = NSRect(x: 0, y: 0, width: 128, height: 128)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return [] }

        var bytes = Array(UnsafeBufferPointer(start: data, count: side * side * 4))
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 0 {
            let alpha = Int(bytes[i + 3])
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, Int(bytes[i + c]) * 255 / alpha)) }
        }
        return bytes
    }
}

/// Where TenFoot saves things: ~/Library/Application Support/TenFoot/
enum StorageLocation {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TenFoot", isDirectory: true)
    }
    static var library: URL { directory.appendingPathComponent("library.json") }
    static var preferences: URL { directory.appendingPathComponent("preferences.json") }
}
