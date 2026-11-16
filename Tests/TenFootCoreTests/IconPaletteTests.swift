import Testing
@testable import TenFootCore

struct IconPaletteTests {
    private func pixels(_ colors: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        colors.flatMap { [$0.0, $0.1, $0.2, $0.3] }
    }

    @Test func keepsEachVividHueInsteadOfAveraging() {
        // Mostly white, with red and blue patches: the average would be a pale purple-grey.
        let icon = pixels(Array(repeating: (255, 255, 255, 255), count: 60)
            + Array(repeating: (230, 20, 20, 255), count: 25)
            + Array(repeating: (20, 40, 230, 255), count: 15))
        let colors = IconPalette.colors(rgba: icon)
        #expect(colors.count == 2)
        #expect(colors[0].red > 0.8 && colors[0].blue < 0.2)  // red first: more of it
        #expect(colors[1].blue > 0.8 && colors[1].red < 0.2)
    }

    @Test func greyIconGivesItsAverage() {
        let icon = pixels(Array(repeating: (100, 100, 100, 255), count: 10) + Array(repeating: (200, 200, 200, 255), count: 10))
        let colors = IconPalette.colors(rgba: icon)
        #expect(colors.count == 1)
        #expect(abs(colors[0].red - 150.0 / 255) < 0.001)
    }

    @Test func ignoresTransparentPixelsAndTinySpecks() {
        let icon = pixels(Array(repeating: (0, 200, 0, 0), count: 50)     // transparent green
            + Array(repeating: (240, 160, 20, 255), count: 98)              // orange
            + Array(repeating: (20, 20, 240, 255), count: 2))               // a speck of blue
        let colors = IconPalette.colors(rgba: icon)
        #expect(colors.count == 1)
        #expect(colors[0].red > 0.9)
        #expect(IconPalette.colors(rgba: pixels(Array(repeating: (9, 9, 9, 0), count: 4))).isEmpty)
    }

    @Test func limitsTheCount() {
        let hues: [(UInt8, UInt8, UInt8, UInt8)] = [(255, 0, 0, 255), (255, 255, 0, 255), (0, 255, 0, 255),
                                                     (0, 255, 255, 255), (0, 0, 255, 255), (255, 0, 255, 255)]
        let icon = pixels(hues.flatMap { Array(repeating: $0, count: 10) })
        #expect(IconPalette.colors(rgba: icon, count: 4).count == 4)
    }
}
