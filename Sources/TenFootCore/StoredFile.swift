import Foundation

/// Keeping a saved file that couldn't be read, so it isn't overwritten.
public enum StoredFile {
    /// Moves an unreadable file aside to `<name>.unreadable-<date>` next to it, so the
    /// next save doesn't replace what was in it. Returns the new location, or nil if
    /// there was nothing to move or it couldn't be moved.
    @discardableResult
    public static func setAside(_ url: URL, at date: Date = Date()) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).unreadable-\(formatter.string(from: date))")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return aside
        } catch {
            return nil
        }
    }
}
