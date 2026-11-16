/// Picks the main colours out of an icon, for the backdrop behind the focused game.
///
/// Averaging a whole icon gives a muddy colour (the petals of a colourful flower
/// average to grey), so vivid pixels are grouped by hue instead and the strongest
/// groups are kept, each as the average of its own pixels.
public enum IconPalette {
    public struct RGB: Equatable, Sendable {
        public var red, green, blue: Double // 0...1
        public init(red: Double, green: Double, blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }
    }

    static let hueBins = 12
    static let minSaturation = 0.25 // greyer than this doesn't count as a colour
    static let minBrightness = 0.15 // darker than this doesn't either
    static let minShare = 0.04      // a hue needs this share of the vivid weight to be kept

    /// Up to `count` colours, strongest first. `pixels` is RGBA, 8 bits each, not
    /// premultiplied. An icon with no clear colours (all grey, black or white) gives
    /// its average colour, or nothing if every pixel is transparent.
    public static func colors(rgba pixels: [UInt8], count: Int = 4) -> [RGB] {
        var bins = [(weight: Double, red: Double, green: Double, blue: Double)](repeating: (0, 0, 0, 0), count: hueBins)
        var plain = (weight: 0.0, red: 0.0, green: 0.0, blue: 0.0)

        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            plain.weight += 1; plain.red += r; plain.green += g; plain.blue += b

            let (hue, saturation, brightness) = hsb(r, g, b)
            guard saturation >= minSaturation, brightness >= minBrightness else { continue }
            let weight = saturation * brightness
            let bin = min(hueBins - 1, Int(hue * Double(hueBins)))
            bins[bin].weight += weight
            bins[bin].red += r * weight; bins[bin].green += g * weight; bins[bin].blue += b * weight
        }

        let total = bins.reduce(0) { $0 + $1.weight }
        let kept = bins
            .filter { total > 0 && $0.weight / total >= minShare }
            .sorted { $0.weight > $1.weight }
            .prefix(count)
            .map { RGB(red: $0.red / $0.weight, green: $0.green / $0.weight, blue: $0.blue / $0.weight) }
        if !kept.isEmpty { return Array(kept) }
        guard plain.weight > 0 else { return [] }
        return [RGB(red: plain.red / plain.weight, green: plain.green / plain.weight, blue: plain.blue / plain.weight)]
    }

    /// Hue (0..<1), saturation and brightness of an RGB colour.
    static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b), range = maximum - minimum
        let saturation = maximum == 0 ? 0 : range / maximum
        guard range > 0 else { return (0, saturation, maximum) }
        var hue: Double
        if maximum == r { hue = (g - b) / range }
        else if maximum == g { hue = 2 + (b - r) / range }
        else { hue = 4 + (r - g) / range }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, maximum)
    }
}
