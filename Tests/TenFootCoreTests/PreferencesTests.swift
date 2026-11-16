import Foundation
import Testing
@testable import TenFootCore

@Suite struct PreferencesTests {
    @Test func defaultsToMatchingMacOS() {
        #expect(Preferences().iconStyle == .matchMacOS)
    }

    @Test func savesAndLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("preferences.json")

        var preferences = Preferences()
        preferences.iconStyle = .fullColour
        try preferences.save(to: file)

        #expect(try Preferences.load(from: file) == preferences)
    }

    @Test func missingFileGivesDefaults() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        #expect(try Preferences.load(from: file) == Preferences())
    }

    @Test func unknownIconStyleGetsDefault() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(#"{"iconStyle": "sparkly"}"#.utf8))
        #expect(decoded == Preferences())
    }

    @Test func missingSettingGetsDefault() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(decoded == Preferences())
    }
}
