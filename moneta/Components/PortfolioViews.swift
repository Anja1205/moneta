import SwiftUI

/// Total value, today's change and total gain across positions.
struct PortfolioHeader: View {
    let portfolio: MarketStore.Portfolio

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your portfolio")
                    .font(.mCaption)
                    .foregroundStyle(Palette.muted)
                Text(Fmt.price(portfolio.value, currency: portfolio.currency))
                    .font(.moneta(size: 34, weight: .bold, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: portfolio.value))
                    .animation(.snappy, value: portfolio.value)
                HStack(spacing: 16) {
                    figure("Today", portfolio.today, base: portfolio.value - portfolio.today)
                    if let gain = portfolio.gain {
                        figure("Total gain", gain, base: portfolio.costBasis)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: String, _ amount: Double, base: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.mCaption)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 6) {
                Text(Fmt.signedPrice(amount, currency: portfolio.currency))
                    .font(.mBodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(Palette.change(amount))
                if base > 0 {
                    ChangeCapsule(fraction: amount / base)
                }
            }
        }
    }
}

/// Thin bar from bearish (red) to bullish (green) with a marker at the score.
struct SentimentBar: View {
    let score: Double

    var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * min(max(score, 0), 100) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Palette.down, Palette.muted, Palette.up], startPoint: .leading, endPoint: .trailing))
                    .opacity(0.45)
                Circle()
                    .fill(Palette.text)
                    .frame(width: 8, height: 8)
                    .offset(x: x - 4)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Sentiment \(Int(score)) of 100")
    }
}

/// Stock detail: sentiment score with the gauge bar and the last week's bullish/bearish counts.
struct SentimentCard: View {
    let sentiment: Sentiment

    private var label: String {
        switch sentiment.score {
        case ..<35: "Bearish"
        case 65...: "Bullish"
        default: "Neutral"
        }
    }

    private var color: Color {
        switch sentiment.score {
        case ..<35: Palette.down
        case 65...: Palette.up
        default: Palette.secondary
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Web sentiment")
                        .font(.mCaption)
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Text("\(sentiment.signals24h) signals in 24h")
                        .font(.mCaption)
                        .foregroundStyle(Palette.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(sentiment.score.rounded()))")
                        .font(.moneta(size: 34, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                    Text("/ 100 · \(label)")
                        .font(.mBodyStrong)
                        .foregroundStyle(color)
                }
                SentimentBar(score: sentiment.score)
                HStack(spacing: 14) {
                    Label("\(sentiment.bullish7d) bullish", systemImage: "arrow.up.right")
                        .foregroundStyle(Palette.up)
                    Label("\(sentiment.bearish7d) bearish", systemImage: "arrow.down.right")
                        .foregroundStyle(Palette.down)
                    Text("last 7 days")
                        .foregroundStyle(Palette.muted)
                }
                .font(.mFootnote)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stock detail: shares, average cost, value and gain, with an Edit button.
struct PositionCard: View {
    let ticker: String
    let position: Position?
    let quote: Quote?
    let edit: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your position")
                        .font(.mCaption)
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button(position?.isEmpty == false ? "Edit" : "Add", action: edit)
                        .font(.mSubheadline)
                        .foregroundStyle(Palette.amber)
                        .frame(minHeight: 44)
                }
                if let position, !position.isEmpty, let shares = position.shares {
                    HStack(alignment: .top, spacing: 20) {
                        figure("Shares", Fmt.number(shares))
                        if let avg = position.avgCost, let quote {
                            figure("Avg cost", Fmt.price(avg, currency: quote.currency))
                        }
                        if let quote {
                            figure("Value", Fmt.price(shares * quote.price, currency: quote.currency))
                        }
                    }
                    if let avg = position.avgCost, let quote, avg > 0 {
                        let gain = shares * (quote.price - avg)
                        HStack(spacing: 6) {
                            Text("Gain")
                                .foregroundStyle(Palette.muted)
                            Text(Fmt.signedPrice(gain, currency: quote.currency))
                                .monospacedDigit()
                                .foregroundStyle(Palette.change(gain))
                            ChangeCapsule(fraction: quote.price / avg - 1)
                        }
                        .font(.mSubheadline)
                    }
                } else {
                    Text("Add how many \(ticker) shares you own to see your value and gain.")
                        .font(.mCallout)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.mCaption).foregroundStyle(Palette.muted)
            Text(value).font(.mBodyStrong).monospacedDigit().foregroundStyle(Palette.text)
        }
    }
}

/// Edit shares and average cost; "Remove position" clears both.
struct PositionEditSheet: View {
    let ticker: String
    let position: Position?
    let currency: String
    let save: (Double?, Double?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shares = ""
    @State private var avgCost = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var sharesValue: Double? { Self.parse(shares) }
    private var avgValue: Double? { avgCost.isEmpty ? nil : Self.parse(avgCost) }
    private var isValid: Bool {
        guard let sharesValue, sharesValue > 0 else { return false }
        return avgCost.isEmpty || (avgValue ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                field("Shares", text: $shares, prompt: "e.g. 10")
                field("Average cost per share (\(currency))", text: $avgCost, prompt: "Optional")
                Spacer()
                PrimaryButton("Save", isLoading: isSaving) {
                    Task {
                        isSaving = true
                        await save(sharesValue, avgValue)
                        isSaving = false
                        dismiss()
                    }
                }
                .disabled(!isValid)
                if position?.isEmpty == false {
                    Button("Remove position", role: .destructive) {
                        Task {
                            await save(nil, nil)
                            dismiss()
                        }
                    }
                    .font(.mBodyStrong)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Palette.down)
                }
            }
            .padding(Metrics.margin)
            .monetaScreen()
            .navigationTitle("\(ticker) position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .onAppear {
            shares = position?.shares.map(Fmt.number) ?? ""
            avgCost = position?.avgCost.map { String(format: "%.2f", $0) } ?? ""
            focused = true
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.mCaption)
                .foregroundStyle(Palette.muted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Palette.muted))
                .keyboardType(.decimalPad)
                .font(.mBodyStrong)
                .foregroundStyle(Palette.text)
                .tint(Palette.amber)
                .focused($focused, equals: true)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
    }
}

/// Grey placeholder tile while the watchlist loads.
struct SkeletonTile: View {
    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 10).frame(width: 32, height: 32)
                Capsule().frame(width: 60, height: 14)
                Capsule().frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 6).frame(height: 38)
                Capsule().frame(width: 80, height: 16)
            }
            .foregroundStyle(Palette.raised)
        }
        .shimmer()
        .accessibilityHidden(true)
    }
}
