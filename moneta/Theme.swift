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

    static let cornerRadius: CGFloat = 20
    static let smallRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 16

    // MARK: Layout

    /// Space inside every card.
    static let cardPadding: CGFloat = 16
    /// Space between cards in a stack.
    static let cardSpacing: CGFloat = 12
    /// Leading/trailing screen margin.
    static let margin: CGFloat = 16

    // MARK: Type
    // Text styles whose default sizes match the scale (34 / 17 / 15 / 12), so they follow Dynamic Type.

    /// 34 bold.
    static let title = Font.largeTitle.bold()
    /// 22 bold, for section titles inside a screen.
    static let sectionTitle = Font.title2.bold()
    /// 17 semibold.
    static let headline = Font.headline
    /// 15 regular.
    static let body = Font.subheadline
    /// 15 semibold.
    static let bodyEmphasis = Font.subheadline.weight(.semibold)
    /// 12 regular.
    static let caption = Font.caption
    /// 12 bold, tracked, uppercase section labels.
    static let label = Font.caption.weight(.bold)

    /// SF Pro Rounded for numbers and prices. Pair with `.monospacedDigit()`.
    static func number(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

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

/// The one card style: #16191E fill, 20pt continuous corners, 1pt white 6% border, 16pt padding.
struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.cardPadding
    var highlighted = false
    /// Overrides the border colour (e.g. gold for a featured card).
    var border: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(Theme.card, in: shape)
            .overlay(
                shape.strokeBorder(
                    highlighted ? Theme.gold.opacity(0.8) : (border ?? Theme.stroke),
                    lineWidth: highlighted ? 1.5 : 1
                )
            )
            .shadow(color: highlighted ? Theme.gold.opacity(0.22) : .clear, radius: 12)
            .animation(.easeOut(duration: 0.3), value: highlighted)
    }
}

extension View {
    /// Wraps the view in the shared card. Pass `padding: 0` when the content lays out its own rows.
    func card(padding: CGFloat = Theme.cardPadding, highlighted: Bool = false, border: Color? = nil) -> some View {
        modifier(CardBackground(padding: padding, highlighted: highlighted, border: border))
    }

    /// Uppercase, tracked caption used above card content.
    func sectionLabelStyle(_ color: Color = Theme.textTertiary) -> some View {
        self
            .font(Theme.label)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Uppercase label above a card or group.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textTertiary

    init(_ text: String, color: Color = Theme.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).sectionLabelStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Gold glow

/// Faint, slowly breathing gold light. Place behind the wordmark or a hero number.
struct GoldGlow: View {
    var width: CGFloat = 300
    var height: CGFloat = 150
    var intensity: Double = 1
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [Theme.gold.opacity(0.32 * intensity), Theme.gold.opacity(0.07 * intensity), .clear],
                    center: .center,
                    startRadius: 2,
                    endRadius: max(width, height) / 2
                )
            )
            .frame(width: width, height: height)
            .blur(radius: height / 6)
            .scaleEffect(breathing ? 1.08 : 0.94)
            .opacity(breathing ? 1 : 0.7)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// The serif "Moneta" wordmark with its gold glow.
struct Wordmark: View {
    var size: CGFloat = 28
    var glow = true

    var body: some View {
        Text("Moneta")
            .font(Theme.wordmark(size: size))
            .foregroundStyle(Theme.gold)
            .fixedSize()
            .background {
                if glow {
                    GoldGlow(width: size * 4.6, height: size * 2.2, intensity: size > 40 ? 1 : 0.8)
                }
            }
            .accessibilityAddTraits(.isHeader)
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
        .lineLimit(1)
        .fixedSize()
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
                .font(.system(size: 11, weight: .bold))
                .fixedSize()
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

/// Press feedback for tappable cards: a small scale-down with a quick spring back.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.03 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Press feedback for buttons and icon buttons.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Full-width gold call to action.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(Theme.background)
                } else {
                    HStack(spacing: 8) {
                        if let systemImage { Image(systemName: systemImage) }
                        Text(title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .font(Theme.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(Theme.background)
            .background(
                Theme.gold.opacity(isEnabled || isLoading ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .disabled(!isEnabled || isLoading)
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
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
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

// MARK: - Prices

enum PriceFormat {
    static func money(_ value: Double?, currency: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency).precision(.fractionLength(value.magnitude < 1 ? 4 : 2)))
    }

    static func signedMoney(_ value: Double?, currency: String) -> String {
        guard let value else { return "—" }
        let body = money(value.magnitude, currency: currency)
        return value > 0 ? "+\(body)" : value < 0 ? "−\(body)" : body
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        let body = value.magnitude.formatted(.number.precision(.fractionLength(2)))
        return value > 0 ? "+\(body)%" : value < 0 ? "−\(body)%" : "\(body)%"
    }

    /// Compact axis label without the currency: "712K", "228.5".
    static func axis(_ value: Double) -> String {
        value.magnitude >= 10_000
            ? value.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
            : value.formatted(.number.precision(.fractionLength(value.magnitude < 10 ? 2...2 : 0...1)))
    }

    /// "$", "€", "US$"… for a currency code, in the user's locale.
    static func symbol(for currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.currencySymbol ?? currency
    }

    /// "10 shares", "1 share", "2.5 shares".
    static func shareCount(_ value: Double) -> String {
        "\(shares(value)) \(value == 1 ? "share" : "shares")"
    }

    static func shares(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }
}

/// Price change as a coloured pill: arrow + percent (or amount when there's no percent).
struct PriceChangePill: View {
    enum Size { case small, regular }

    let percent: Double?
    var change: Double? = nil
    var currency: String = "USD"
    var size: Size = .small

    private var value: Double? { percent ?? change }

    private var color: Color {
        guard let value, value != 0 else { return Theme.neutral }
        return value > 0 ? Theme.bullish : Theme.bearish
    }

    private var symbol: String {
        guard let value, value != 0 else { return "minus" }
        return value > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var text: String {
        percent != nil ? PriceFormat.percent(percent) : PriceFormat.signedMoney(change, currency: currency)
    }

    var body: some View {
        HStack(spacing: size == .small ? 3 : 4) {
            Image(systemName: symbol)
                .font(.system(size: size == .small ? 9 : 11, weight: .heavy))
                .contentTransition(.symbolEffect(.replace))
            Text(text)
                .monospacedDigit()
                .contentTransition(.numericText(value: value ?? 0))
        }
        .font(Theme.number(size == .small ? .caption : .subheadline, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(color)
        .padding(.horizontal, size == .small ? 8 : 10)
        .padding(.vertical, size == .small ? 3 : 5)
        .background(color.opacity(0.15), in: Capsule())
        .animation(.snappy, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let value, value != 0 else { return "Unchanged" }
        return "\(value > 0 ? "Up" : "Down") \(text.dropFirst())"
    }
}

/// Small "DEMO" tag for stocks the backend marks `is_demo`.
struct DemoTag: View {
    var body: some View {
        Text("DEMO")
            .font(.system(size: 9, weight: .bold))
            .fixedSize()
            .tracking(0.6)
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1))
            .accessibilityLabel("Demo stock")
    }
}

// MARK: - Price flash

/// Brief green/red highlight behind a price when a live update moves it.
struct PriceFlash: ViewModifier {
    let direction: Direction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(direction.map { Theme.color(for: $0).opacity(0.28) } ?? .clear)
            )
            .padding(.horizontal, -4)
            .animation(reduceMotion ? nil : (direction == nil ? .easeOut(duration: 0.8) : .easeIn(duration: 0.12)), value: direction)
    }
}

extension View {
    func priceFlash(_ direction: Direction?) -> some View {
        modifier(PriceFlash(direction: direction))
    }
}

extension RelativeTime {
    /// "Updated just now", "Updated 4 min ago", "Updated 3 h ago", "Updated 2 d ago".
    static func updated(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(max(now.timeIntervalSince(date), 0) / 60)
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        case ..<(48 * 60): return "Updated \(minutes / 60) h ago"
        default: return "Updated \(minutes / 1440) d ago"
        }
    }
}
