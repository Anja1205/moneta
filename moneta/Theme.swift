import SwiftUI

enum Theme {
    static let background = Color(hex: "#0B0D10")
    static let card = Color(hex: "#16191E")
    static let cardRaised = Color(hex: "#1D2127")
    static let stroke = Color.white.opacity(0.06)
    static let gold = Color(hex: "#E8B44A")
    static let bullish = Color(hex: "#2ECC71")
    static let bearish = Color(hex: "#FF4D5E")
    static let neutral = Color(hex: "#8A8F98")
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let cornerRadius: CGFloat = 18
    static let smallRadius: CGFloat = 12

    static func color(for direction: Direction) -> Color {
        switch direction {
        case .bullish: bullish
        case .bearish: bearish
        case .neutral: neutral
        }
    }

    static func wordmark(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

extension Color {
    /// Accepts `#RGB`, `#RRGGBB` or `#RRGGBBAA`. Falls back to neutral grey.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        guard (s.count == 6 || s.count == 8), Scanner(string: s).scanHexInt64(&value) else {
            self = Color(red: 0.54, green: 0.56, blue: 0.6)
            return
        }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

struct CardBackground: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.gold.opacity(0.7) : Theme.stroke, lineWidth: highlighted ? 1.2 : 1)
            )
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View {
        modifier(CardBackground(highlighted: highlighted))
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func string(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "—" }
        if now.timeIntervalSince(date) < 45 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
