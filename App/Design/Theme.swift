import SwiftUI

/// The app's look in one place: colours, type and the few building blocks every
/// screen uses. Reskin here, not in the screens.
enum Theme {
    /// Paint-swatch accent: coral into magenta.
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let accent2 = Color(red: 0.96, green: 0.23, blue: 0.53)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let doneGradient = LinearGradient(colors: [Color(red: 0.2, green: 0.85, blue: 0.55), Color(red: 0.1, green: 0.7, blue: 0.75)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static let background = Color(red: 0.035, green: 0.035, blue: 0.05)
    static let surface = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.09)

    static let good = Color(red: 0.25, green: 0.86, blue: 0.56)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.24)
    static let bad = Color(red: 1.0, green: 0.33, blue: 0.33)
    static let door = Color(red: 0.98, green: 0.66, blue: 0.38)
    static let window = Color(red: 0.42, green: 0.8, blue: 1.0)

    static let corner: CGFloat = 24
}

extension Font {
    /// Rounded figures for measurements.
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Solid card on the dark background.
    func card(padding: CGFloat = 18, cornerRadius: CGFloat = Theme.corner) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }

    /// Floating panel over the camera: Liquid Glass on iOS 26+, frosted material before.
    func glassPanel(cornerRadius: CGFloat = Theme.corner, tint: Color? = nil) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint))
    }

    func sectionTitle() -> some View {
        self
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular,
                                in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
        }
    }
}

/// Big gradient capsule for the one main action on a screen.
struct GradientButtonStyle: ButtonStyle {
    var gradient = Theme.gradient
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 24)
            .background(gradient, in: Capsule())
            .shadow(color: Theme.accent.opacity(isEnabled ? 0.35 : 0), radius: 18, y: 8)
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Small coloured tag, e.g. a measurement flag.
struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

/// A labelled figure: "CEILING  16.3 m²".
struct StatTile: View {
    let title: String
    /// Formatted value with its unit after a space, e.g. "16.3 m²".
    let value: String
    var detail: String? = nil

    var body: some View {
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        VStack(alignment: .leading, spacing: 6) {
            Text(title).sectionTitle()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.first ?? value)
                    .font(.number(30))
                    .monospacedDigit()
                if parts.count > 1 {
                    Text(parts[1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 20)
    }
}

/// Round badge with a short label, e.g. a wall letter.
struct Badge: View {
    let text: String
    var filled = true

    var body: some View {
        Text(text)
            .font(.number(15, weight: .heavy))
            .foregroundStyle(filled ? .white : Theme.accent)
            .frame(width: 36, height: 36)
            .background {
                if filled {
                    Circle().fill(Theme.gradient)
                } else {
                    Circle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 2)
                }
            }
    }
}

/// Screen background: near-black with a faint warm glow in one corner.
struct BackdropView: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accent2.opacity(0.16), .clear], center: .topTrailing, startRadius: 20, endRadius: 520)
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear], center: .bottomLeading, startRadius: 20, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}
