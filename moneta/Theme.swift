import SwiftUI

// MARK: - Tokens

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

    /// Serif face for the "Moneta" wordmark and display titles.
    static func wordmark(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

extension Color {
    /// Accepts `#RGB`, `#RRGGBB` or `#RRGGBBAA`, with or without `#`. Falls back to neutral grey.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        guard s.count == 6 || s.count == 8, Scanner(string: s).scanHexInt64(&value) else {
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

// MARK: - Card surface

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

// MARK: - DirectionBadge

struct DirectionBadge: View {
    enum Size { case normal, large }

    let direction: Direction
    var size: Size = .normal

    var body: some View {
        let color = Theme.color(for: direction)
        HStack(spacing: size == .large ? 6 : 4) {
            Image(systemName: direction.symbol)
                .fontWeight(.bold)
            Text(direction.label)
        }
        .font(size == .large ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, size == .large ? 12 : 8)
        .padding(.vertical, size == .large ? 7 : 4)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ImpactMeter

struct ImpactMeter: View {
    let impact: Int
    var direction: Direction = .neutral
    var dotSize: CGFloat = 6

    private var level: Int { min(max(impact, 0), 5) }

    var body: some View {
        HStack(spacing: dotSize * 0.6) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= level ? Theme.color(for: direction) : Color.white.opacity(0.12))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Impact \(level) of 5")
    }
}

// MARK: - SourceChip

struct SourceChip: View {
    let kind: SourceKind
    var sourceName: String?

    private var label: String {
        if let sourceName, !sourceName.trimmingCharacters(in: .whitespaces).isEmpty { return sourceName }
        return kind.label
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
            Text(label)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - StockLogo

struct StockLogo: View {
    let ticker: String
    let logoURL: String?
    let brandColor: String?
    var size: CGFloat = 36

    init(ticker: String, logoURL: String?, brandColor: String?, size: CGFloat = 36) {
        self.ticker = ticker
        self.logoURL = logoURL
        self.brandColor = brandColor
        self.size = size
    }

    init(stock: Stock, size: CGFloat = 36) {
        self.init(ticker: stock.ticker, logoURL: stock.logoURL, brandColor: stock.brandColor, size: size)
    }

    private var tint: Color { brandColor.map(Color.init(hex:)) ?? Theme.gold }

    private var initials: String {
        String(ticker.filter(\.isLetter).prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            AsyncImage(url: logoURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.2)
                } else {
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .accessibilityLabel(ticker)
    }
}

// MARK: - LivePill

struct LivePill: View {
    let isLive: Bool
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if isLive {
                    Circle()
                        .fill(Theme.bearish.opacity(0.45))
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulsing ? 1.5 : 0.5)
                        .opacity(pulsing ? 0 : 1)
                }
                Circle()
                    .fill(isLive ? Theme.bearish : Theme.neutral)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 14, height: 14)
            Text(isLive ? "LIVE" : "OFFLINE")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(isLive ? Theme.textPrimary : Theme.neutral)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(isLive ? Theme.bearish.opacity(0.12) : Color.white.opacity(0.05), in: Capsule())
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared pieces

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.bearish)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Theme.bearish.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .strokeBorder(Theme.bearish.opacity(0.25))
        )
    }
}
