import ActivityKit
import SwiftUI
import WidgetKit

private enum WidgetTheme {
    static let background = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255)
    static let gold = Color(red: 0xE8 / 255, green: 0xB4 / 255, blue: 0x4A / 255)
    static let secondary = Color.white.opacity(0.65)
    static let dimDot = Color.white.opacity(0.18)

    /// The app's M mark on its dark tile.
    static func mark(_ size: CGFloat) -> some View {
        Image("MonetaMark")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }

    static func color(for state: MonetaAttributes.ContentState) -> Color {
        let rgb = state.directionRGB
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct MonetaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonetaAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(WidgetTheme.background)
                .activitySystemActionForegroundColor(WidgetTheme.gold)
        } dynamicIsland: { context in
            let state = context.state
            let color = WidgetTheme.color(for: state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        WidgetTheme.mark(22)
                        Text(state.ticker)
                            .font(.headline.weight(.bold))
                        Image(systemName: state.arrowSymbol)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(color)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ImpactDots(impact: state.impact, color: color, size: 7)
                        .padding(.trailing, 4)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(state.why)
                        .font(.footnote)
                        .foregroundStyle(WidgetTheme.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    WidgetTheme.mark(16)
                    Text(state.ticker)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetTheme.gold)
                }
            } compactTrailing: {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
            } minimal: {
                WidgetTheme.mark(18)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(color).frame(width: 6, height: 6).offset(x: 2, y: -2)
                    }
            }
            .keylineTint(WidgetTheme.gold)
        }
    }
}

private struct LockScreenView: View {
    let state: MonetaAttributes.ContentState

    var body: some View {
        let color = WidgetTheme.color(for: state)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                WidgetTheme.mark(22)
                Text("Moneta")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetTheme.gold)
                Spacer()
                Text(state.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.secondary)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Text(state.ticker)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Label(state.directionLabel, systemImage: state.arrowSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                if state.impact > 0 {
                    ImpactDots(impact: state.impact, color: color, size: 6)
                }
            }
            Text(state.why)
                .font(.subheadline)
                .foregroundStyle(WidgetTheme.secondary)
                .lineLimit(2)
        }
        .padding(16)
    }
}

private struct ImpactDots: View {
    let impact: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= impact ? color : WidgetTheme.dimDot)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Impact \(impact) of 5")
    }
}

#Preview("Lock Screen", as: .content, using: MonetaAttributes()) {
    MonetaLiveActivity()
} contentStates: {
    MonetaAttributes.ContentState(ticker: "NVDA", direction: "bearish", why: "CEO resignation wipes $1T in value as investors question succession.", impact: 4, updatedAt: .now)
    MonetaAttributes.ContentState(ticker: "MSFT", direction: "bullish", why: "New AI pricing tier spotted on the pricing page before any announcement.", impact: 3, updatedAt: .now)
}
