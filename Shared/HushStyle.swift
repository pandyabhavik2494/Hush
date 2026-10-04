import SwiftUI

/// Hush's look, shared by the iPhone and Mac apps: black, warm gold, quiet type.
enum HushStyle {
    static let paper = Color(red: 0.040, green: 0.039, blue: 0.037)
    static let surface = Color(red: 0.085, green: 0.083, blue: 0.078)
    static let ink = Color(red: 0.945, green: 0.936, blue: 0.906)
    static let muted = Color(red: 0.610, green: 0.604, blue: 0.584)
    static let gold = Color(red: 0.790, green: 0.660, blue: 0.420)
    static let line = Color(red: 0.180, green: 0.173, blue: 0.155)

    static func brandFont(size: CGFloat) -> Font {
        .custom("Baskerville-SemiBoldItalic", size: size, relativeTo: .largeTitle)
    }

    /// "42 min" / "1 hr 5 min" for a total length in seconds.
    static func durationText(_ seconds: TimeInterval) -> String? {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}

/// Hush's own backdrop for the Liquid Glass header: soft pools of gold, bronze and deep wine light
/// at the top of the library, melting into black. Liquid Glass needs something to bend — over plain
/// black it just looks grey — and this gives it that without ever following the playing album.
/// Fixed and static (glass must never animate), purely decorative.
struct HushAmbientLight: View {
    private static let bronze = Color(red: 0.56, green: 0.34, blue: 0.14)
    private static let wine = Color(red: 0.36, green: 0.12, blue: 0.15)

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack {
                // Gold, top left.
                RadialGradient(
                    colors: [HushStyle.gold.opacity(0.34), HushStyle.gold.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.12, y: -0.02),
                    startRadius: 0,
                    endRadius: width * 0.85
                )
                // Bronze, top right.
                RadialGradient(
                    colors: [Self.bronze.opacity(0.38), Self.bronze.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.92, y: 0.06),
                    startRadius: 0,
                    endRadius: width * 0.8
                )
                // A little deep wine lower down, for depth.
                RadialGradient(
                    colors: [Self.wine.opacity(0.30), .clear],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: width * 0.7
                )
            }
            .frame(width: geometry.size.width, height: 520)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
