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
            VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                header
                impactSection
                whyCard
                details
                    .padding(.top, 8)
                actions
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .demoScrollAnchor()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(signal.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSource) {
            if let sourceURL {
                SafariView(url: sourceURL)
                    .ignoresSafeArea()
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CompanyLogo(ticker: signal.ticker, logoURL: stock?.logoURL, brandColor: stock?.brandColor, size: .header)
            VStack(alignment: .leading, spacing: 4) {
                Text(signal.ticker)
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(signal.stockName)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DirectionBadge(direction: signal.direction, size: .large)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Impact")
            HStack(alignment: .center) {
                ImpactMeter(impact: signal.clampedImpact, direction: signal.direction, dotSize: 18)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(signal.clampedImpact)")
                        .font(Theme.number(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.color(for: signal.direction))
                    Text("/5")
                        .font(Theme.number(.title3))
                        .foregroundStyle(Theme.textTertiary)
                }
                .monospacedDigit()
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Theme.gold.opacity(0.35))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            SourceChip(kind: signal.sourceKind, sourceName: signal.sourceName)

            Text(signal.title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let description = signal.description, !description.isEmpty {
                Text(description)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(publishedText, systemImage: "clock")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if sourceURL != nil {
                PrimaryButton(title: "Open source", systemImage: "safari") { showingSource = true }
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
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Share")
        }
        .padding(.top, 4)
    }

    private var shareLabel: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.gold)
            .frame(width: 52, height: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
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
