import SwiftUI

struct SignalDetailView: View {
    let signal: Signal
    let stock: Stock?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var articleURL: URL? { signal.url.flatMap(URL.init(string:)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let urlString = signal.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Theme.card
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }

                HStack(spacing: 10) {
                    StockLogo(ticker: signal.ticker, logoURL: stock?.logoURL, brandColor: stock?.brandColor, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.ticker)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(stock?.domain ?? signal.stockName)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    DirectionBadge(direction: signal.direction)
                }

                Text(signal.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Why it matters", systemImage: "sparkle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                        Spacer()
                        ImpactMeter(impact: signal.clampedImpact, direction: signal.direction, barWidth: 6)
                        Text("\(signal.clampedImpact)/5")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(signal.why)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .card()

                if let description = signal.description, !description.isEmpty, description != signal.why {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    MetaRow(symbol: signal.sourceKind.symbol, label: "Source",
                            value: [signal.sourceKind.label, signal.sourceName].compactMap { $0 }.joined(separator: " · "))
                    Divider().overlay(Theme.stroke)
                    MetaRow(symbol: "clock", label: "Published",
                            value: signal.publishedDate.map(Self.dateText) ?? "Unknown")
                    Divider().overlay(Theme.stroke)
                    MetaRow(symbol: "dot.radiowaves.up.forward", label: "Detected",
                            value: signal.detectedDate.map(Self.dateText) ?? "Unknown")
                    if let lead = leadTime {
                        Divider().overlay(Theme.stroke)
                        MetaRow(symbol: "bolt", label: "Picked up", value: lead)
                    }
                }
                .padding(.horizontal, 16)
                .card()

                if let articleURL {
                    Button {
                        openURL(articleURL)
                    } label: {
                        Label("Open source", systemImage: "arrow.up.right.square")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.background)
                            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }

    private var leadTime: String? {
        guard let published = signal.publishedDate, let detected = signal.detectedDate else { return nil }
        let seconds = detected.timeIntervalSince(published)
        guard seconds >= 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds < 60 ? [.second] : [.day, .hour, .minute]
        guard let text = formatter.string(from: seconds) else { return nil }
        return "\(text) after publish"
    }

    private static func dateText(_ date: Date) -> String {
        "\(date.formatted(date: .abbreviated, time: .shortened)) · \(RelativeTime.string(for: date))"
    }
}

private struct MetaRow: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Theme.textTertiary)
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 13)
    }
}
