import SafariServices
import SwiftUI

struct SignalDetailView: View {
    let signal: Signal
    let stock: Stock?
    @State private var showingSource = false

    private var sourceURL: URL? {
        guard let raw = signal.url, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private var shareText: String { "\(signal.ticker): \(signal.why)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                impactSection
                whyCard
                details
                actions
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(signal.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSource) {
            if let sourceURL {
                SafariView(url: sourceURL)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            StockLogo(ticker: signal.ticker, logoURL: stock?.logoURL, brandColor: stock?.brandColor, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.ticker)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(signal.stockName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            DirectionBadge(direction: signal.direction, size: .large)
        }
    }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Impact")
            HStack(alignment: .center) {
                ImpactMeter(impact: signal.clampedImpact, direction: signal.direction, dotSize: 18)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(signal.clampedImpact)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.color(for: signal.direction))
                    Text("/5")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                .monospacedDigit()
            }
        }
        .padding(16)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Impact \(signal.clampedImpact) of 5")
    }

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Why it matters", color: Theme.gold)
            Text(signal.why)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1)
        )
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            SourceChip(kind: signal.sourceKind, sourceName: signal.sourceName)

            Text(signal.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let description = signal.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(publishedText, systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if sourceURL != nil {
                Button {
                    showingSource = true
                } label: {
                    Label("Open source", systemImage: "safari")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Theme.background)
                        .background(Theme.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            Group {
                if let sourceURL {
                    ShareLink(item: sourceURL, subject: Text(signal.title), message: Text(shareText)) {
                        shareLabel
                    }
                } else {
                    ShareLink(item: shareText) { shareLabel }
                }
            }
            .accessibilityLabel("Share")
        }
        .padding(.top, 4)
    }

    private var shareLabel: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.gold)
            .frame(width: 52, height: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.4))
            )
    }

    private var publishedText: String {
        if let date = signal.publishedDate {
            return "Published \(date.formatted(date: .abbreviated, time: .shortened)) · \(RelativeTime.string(for: date))"
        }
        if let date = signal.detectedDate {
            return "Detected \(date.formatted(date: .abbreviated, time: .shortened)) · \(RelativeTime.string(for: date))"
        }
        return "Publish time unknown"
    }
}

private struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textTertiary

    init(_ text: String, color: Color = Theme.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// In-app browser for the signal's source.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.gold)
        controller.preferredBarTintColor = UIColor(Theme.background)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
