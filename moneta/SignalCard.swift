import SwiftUI

struct SignalCard: View {
    let signal: Signal
    let stock: Stock?
    let isLive: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StockLogo(
                    ticker: signal.ticker,
                    logoURL: stock?.logoURL,
                    brandColor: stock?.brandColor,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(signal.ticker)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(signal.stockName)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isLive || signal.isNew {
                    Text("NEW")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(isLive ? Theme.background : Theme.gold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isLive ? Theme.gold : Theme.gold.opacity(0.14), in: Capsule())
                }
                Text(RelativeTime.string(for: signal.detectedDate, now: now))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(signal.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text(signal.why)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let urlString = signal.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Theme.cardRaised
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                }
            }

            HStack(spacing: 10) {
                DirectionBadge(direction: signal.direction)
                Label(signal.sourceName ?? signal.sourceKind.label, systemImage: signal.sourceKind.symbol)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ImpactMeter(impact: signal.clampedImpact, direction: signal.direction)
            }
        }
        .padding(16)
        .card(highlighted: isLive)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.color(for: signal.direction))
                .frame(width: 3)
                .padding(.vertical, 18)
                .opacity(signal.clampedImpact >= Config.alertImpact ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
