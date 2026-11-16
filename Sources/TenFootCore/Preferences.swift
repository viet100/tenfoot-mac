import Foundation

/// How app icons are drawn on the home screen.
public enum IconStyle: String, Codable, CaseIterable, Sendable {
    /// The icon as macOS shows it, following the icon style in System Settings → Appearance.
    case matchMacOS
    /// The app's own full-colour icon file, whatever the macOS icon style is.
    case fullColour
}

/// The choices made on the Settings screen.
///
/// Settings missing from the saved file get their default, so new settings can be
/// added over time without losing what's already saved.
public struct Preferences: Codable, Equatable, Sendable {
    public var iconStyle: IconStyle = .matchMacOS

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iconStyle = try container.decodeIfPresent(IconStyle.self, forKey: .iconStyle) ?? .matchMacOS
    }

    /// Loads preferences from `url`; a missing file gives the defaults.
    public static func load(from url: URL) throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
