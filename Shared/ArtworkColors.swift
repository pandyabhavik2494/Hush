import CoreGraphics
import CoreImage

/// The colours of a cover's top and bottom edges, which the Now Playing screen paints its
/// background with (iPhone and Mac).
enum ArtworkColors {
    private static let context = CIContext()

    /// A color as plain 0…1 numbers.
    struct RGB: Sendable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        var brightness: CGFloat { 0.299 * red + 0.587 * green + 0.114 * blue }
    }

    /// Reads the cover's color along its top edge and along its bottom edge (a strip a tenth of the
    /// cover high each), a touch more saturated so it stays lively once shaded.
    static func edgeColors(of source: CIImage) -> (top: RGB, bottom: RGB)? {
        let extent = source.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return nil }
        let input = source.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
        let strip = extent.height * 0.1
        // Core Image counts from the bottom.
        let top = dominantColor(of: input, in: CGRect(x: extent.minX, y: extent.maxY - strip, width: extent.width, height: strip))
        let bottom = dominantColor(of: input, in: CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: strip))
        return (top, bottom)
    }

    /// The most common color in part of an image. A plain average turns a mixed edge (yellow, green
    /// and blue side by side, say) into grey; this finds the biggest group of similar pixels and
    /// averages only those.
    private static func dominantColor(of image: CIImage, in region: CGRect) -> RGB {
        // Shrink the strip to a few dozen pixels across: plenty to count colors.
        let columns = 48
        let scale = CGFloat(columns) / max(region.width, 1)
        let rows = max(Int((region.height * scale).rounded()), 1)
        let small = image
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        context.render(small, toBitmap: &pixels, rowBytes: columns * 4,
                           bounds: CGRect(x: 0, y: 0, width: columns, height: rows),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        // Sort the pixels into 64 coarse color groups (4 levels each of red, green, blue).
        var counts = [Int](repeating: 0, count: 64)
        var reds = [Int](repeating: 0, count: 64)
        var greens = [Int](repeating: 0, count: 64)
        var blues = [Int](repeating: 0, count: 64)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            let group = (red >> 6) << 4 | (green >> 6) << 2 | (blue >> 6)
            counts[group] += 1
            reds[group] += red
            greens[group] += green
            blues[group] += blue
        }
        guard let biggest = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[biggest] > 0 else {
            return RGB(red: 0, green: 0, blue: 0)
        }
        let total = CGFloat(counts[biggest]) * 255
        return RGB(red: CGFloat(reds[biggest]) / total, green: CGFloat(greens[biggest]) / total, blue: CGFloat(blues[biggest]) / total)
    }
}
