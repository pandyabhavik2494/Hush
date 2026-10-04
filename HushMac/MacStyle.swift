import AppKit
import SwiftUI

/// Mac-only additions to Hush's shared style (Shared/HushStyle.swift).
extension HushStyle {
    /// The sidebar and panels: a step up from `paper`.
    static let panel = Color(red: 0.078, green: 0.075, blue: 0.067)
    /// Hover and selection fills.
    static let raised = Color(red: 0.125, green: 0.121, blue: 0.113)
    /// The faint ink-tinted fill behind capsules and fields.
    static let fill = ink.opacity(0.07)
    static let fillStroke = ink.opacity(0.09)
    static let faint = Color(red: 0.369, green: 0.361, blue: 0.341)

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// "3:07" / "1:02:15".
    static func timestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    static func count(_ number: Int) -> String {
        number.formatted(.number)
    }
}

extension View {
    /// Frosted glass behind a floating control (Liquid Glass on macOS 26, a dark material before).
    @ViewBuilder
    func hushGlass<S: Shape>(_ shape: S, tint: Color = Color(red: 0.118, green: 0.110, blue: 0.098).opacity(0.62)) -> some View {
        if #available(macOS 26.0, *) {
            background {
                Color.clear.glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint)
                }
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }

    /// The pointing-hand cursor over something clickable that isn't a standard control.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Buttons

/// The gold capsule ("Play", "Play all").
struct HushPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 38

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(HushStyle.rounded(14, weight: .semibold))
            .foregroundStyle(HushStyle.paper)
            .padding(.horizontal, 20)
            .frame(height: height)
            .background(HushStyle.gold, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The quiet capsule next to it ("Shuffle").
struct HushSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 38

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(HushStyle.rounded(14, weight: .semibold))
            .foregroundStyle(HushStyle.ink)
            .padding(.horizontal, 20)
            .frame(height: height)
            .background(HushStyle.ink.opacity(configuration.isPressed ? 0.14 : 0.08), in: Capsule())
            .overlay(Capsule().stroke(HushStyle.ink.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// A bare icon that brightens under the pointer — transport and bar controls.
struct HushIconButtonStyle: ButtonStyle {
    var isActive = false
    var idle: Color = HushStyle.muted
    var hover: Color = HushStyle.ink

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HushIconButtonBody(configuration: configuration, isActive: isActive, idle: idle, hover: hover)
    }
}

private struct HushIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    let idle: Color
    let hover: Color
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isActive ? HushStyle.gold : (isHovering ? hover : idle))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

/// A round control on a faint fill (toolbar toggles, the Now Playing top buttons).
struct HushCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = 34
    var isOn = false
    var onLight = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.44, weight: .medium))
            .foregroundStyle(isOn ? HushStyle.gold : (onLight ? Color.white : HushStyle.ink.opacity(0.85)))
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(isOn ? HushStyle.gold.opacity(0.16) : (onLight ? Color.white.opacity(0.10) : HushStyle.fill))
            )
            .overlay(Circle().stroke(onLight ? Color.white.opacity(0.14) : HushStyle.fillStroke, lineWidth: 1))
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Lifts a touch while pressed (covers, tiles).
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The round gold play/pause button.
struct PlayPauseButton: View {
    @Environment(Player.self) private var player
    var diameter: CGFloat = 38
    var fill: Color = HushStyle.gold
    var symbolColor: Color = HushStyle.paper

    var body: some View {
        Button {
            player.togglePlayPause()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: diameter * 0.40, weight: .bold))
                .foregroundStyle(symbolColor)
                .contentTransition(.symbolEffect(.replace.downUp))
                .offset(x: player.isPlaying ? 0 : diameter * 0.03)
                .frame(width: diameter, height: diameter)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(player.current == nil)
        .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }
}

/// The gold equaliser bars on the playing row and tile; they move only while music plays.
struct NowPlayingBars: View {
    var isPlaying: Bool
    var color: Color = HushStyle.gold
    var barWidth: CGFloat = 3
    var height: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barWidth * 0.7) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * (5.2 + Double(index) * 1.3) + Double(index) * 1.7
                    let level = isPlaying ? 0.35 + 0.65 * abs(sin(phase)) : [0.6, 1.0, 0.45][index]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: barWidth, height: max(height * level, 2))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .accessibilityLabel("Now playing")
    }
}

/// A scrubber: a thin track that grows a knob under the pointer. Drag or click to move.
struct HushSlider: View {
    /// 0…1.
    let value: Double
    var tint: Color = HushStyle.gold
    var track: Color = HushStyle.ink.opacity(0.14)
    var height: CGFloat = 4
    var alwaysShowsKnob = false
    var knobColor: Color = HushStyle.ink
    let onChange: (Double) -> Void
    var onEnded: ((Double) -> Void)?

    @State private var isHovering = false
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geometry in
            let shown = min(max(dragValue ?? value, 0), 1)
            let width = geometry.size.width
            let knob = height * 3
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: height)
                Capsule().fill(tint).frame(width: max(width * shown, 0), height: height)
                if alwaysShowsKnob || isHovering || dragValue != nil {
                    Circle()
                        .fill(knobColor)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .offset(x: min(max(width * shown - knob / 2, -knob / 2), width - knob / 2))
                        .transition(.opacity)
                }
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max(drag.location.x / max(width, 1), 0), 1)
                        dragValue = fraction
                        onChange(fraction)
                    }
                    .onEnded { drag in
                        let fraction = min(max(drag.location.x / max(width, 1), 0), 1)
                        dragValue = nil
                        (onEnded ?? onChange)(fraction)
                    }
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .frame(height: max(height * 3, 14))
    }
}

/// A small rounded count or label capsule ("158", "TV app").
struct CountCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HushStyle.rounded(11.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(HushStyle.ink.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(HushStyle.fill, in: Capsule())
            .overlay(Capsule().stroke(HushStyle.ink.opacity(0.08), lineWidth: 1))
    }
}

/// Lets the window be dragged from an empty area (the window has no title bar).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
