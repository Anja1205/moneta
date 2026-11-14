import SwiftUI

// MARK: - Position card

/// "Your position" on the stock detail screen.
struct PositionCard: View {
    let stock: Stock
    let holding: Holding
    let edit: () -> Void

    private var code: String { stock.currencyCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel("Your position")
                Spacer()
                if !holding.isEmpty {
                    Button(action: edit) {
                        Text("Edit")
                            .font(Theme.bodyEmphasis)
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(Theme.gold.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Edit position")
                }
            }

            if holding.isEmpty {
                Text("Add how many shares you own to see your value, gain and today’s move.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Add your position", systemImage: "plus", action: edit)
            } else {
                filled
            }
        }
        .card()
    }

    @ViewBuilder
    private var filled: some View {
        let value = holding.marketValue(at: stock.price)
        let gain = holding.gain(at: stock.price)
        let today = holding.todayChange(stock.priceChange)

        VStack(alignment: .leading, spacing: 2) {
            Text(PriceFormat.money(value, currency: code))
                .font(Theme.number(.title, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: value ?? 0))
                .animation(.snappy, value: value)
            Text("Market value")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)

        VStack(spacing: 10) {
            PositionRow(label: "Shares owned", value: PriceFormat.shares(holding.shares ?? 0))
            PositionRow(label: "Average cost", value: PriceFormat.money(holding.avgCost, currency: code))
            Divider().overlay(Theme.stroke)
            PositionRow(
                label: "Total gain/loss",
                value: gain == nil ? "—" : PriceFormat.signedMoney(gain, currency: code),
                amount: gain,
                percent: holding.gainPct(at: stock.price)
            )
            PositionRow(
                label: "Today",
                value: today == nil ? "—" : PriceFormat.signedMoney(today, currency: code),
                amount: today,
                percent: stock.priceChangePct
            )
        }

        if holding.avgCost == nil {
            Text("Add an average buy price to see your total gain.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Label on the left, value (and optional coloured pill) on the right; wraps under at large text.
private struct PositionRow: View {
    let label: String
    let value: String
    /// When set, colours the value green/red by sign.
    var amount: Double? = nil
    var percent: Double? = nil

    private var color: Color {
        guard let amount else { return Theme.textPrimary }
        return amount > 0 ? Theme.bullish : amount < 0 ? Theme.bearish : Theme.neutral
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                labelText
                Spacer(minLength: 8)
                valueGroup
            }
            VStack(alignment: .leading, spacing: 4) {
                labelText
                HStack(spacing: 8) { valueGroup }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(Theme.body)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var valueGroup: some View {
        Text(value)
            .font(Theme.number(.subheadline))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(.numericText(value: amount ?? 0))
            .animation(.snappy, value: amount)
        if amount != nil, percent != nil {
            PriceChangePill(percent: percent)
        }
    }
}

// MARK: - Edit sheet

/// Shares owned and average buy price for one stock, saved on the user's watchlist row.
struct EditPositionSheet: View {
    let stock: Stock
    let holding: Holding

    @Environment(SignalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shares: String
    @State private var avgCost: String
    @State private var isSaving = false
    @State private var serverError: String?
    @State private var showErrors = false
    @FocusState private var focused: Field?

    private enum Field { case shares, cost }

    init(stock: Stock, holding: Holding) {
        self.stock = stock
        self.holding = holding
        let plain: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)) }
        _shares = State(initialValue: holding.shares.map(plain) ?? "")
        _avgCost = State(initialValue: holding.avgCost.map(plain) ?? "")
    }

    // MARK: Validation

    private enum Parsed { case empty, value(Double), invalid }

    /// Accepts "1,5" or "1.5" and ignores grouping spaces.
    private static func parse(_ text: String) -> Parsed {
        let cleaned = String(text.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) })
            .replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty { return .empty }
        guard let value = Double(cleaned), value.isFinite else { return .invalid }
        return .value(value)
    }

    private var sharesError: String? {
        switch Self.parse(shares) {
        case .empty: "Enter how many shares you own."
        case .invalid: "Enter a number, like 10 or 2.5."
        case .value(let v) where v <= 0: "Shares must be more than 0."
        case .value(let v) where v > 1_000_000_000: "That’s more shares than we can track."
        case .value: nil
        }
    }

    private var costError: String? {
        switch Self.parse(avgCost) {
        case .empty: nil // optional
        case .invalid: "Enter a price, like 151.20."
        case .value(let v) where v < 0: "Price can’t be negative."
        case .value: nil
        }
    }

    private var isValid: Bool { sharesError == nil && costError == nil }

    private var sharesValue: Double? {
        if case .value(let v) = Self.parse(shares) { return v }
        return nil
    }

    private var costValue: Double? {
        if case .value(let v) = Self.parse(avgCost) { return v }
        return nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NumberField(
                        label: "Shares owned",
                        prefix: nil,
                        suffix: "shares",
                        placeholder: "0",
                        text: $shares,
                        error: showErrors ? sharesError : nil
                    )
                    .focused($focused, equals: .shares)

                    NumberField(
                        label: "Average buy price",
                        prefix: PriceFormat.symbol(for: stock.currencyCode),
                        suffix: nil,
                        placeholder: "0.00",
                        text: $avgCost,
                        error: showErrors ? costError : nil
                    )
                    .focused($focused, equals: .cost)

                    if let sharesValue, let price = stock.price {
                        Text("Worth \(PriceFormat.money(sharesValue * price, currency: stock.currencyCode)) at today’s price.")
                            .font(Theme.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .contentTransition(.numericText(value: sharesValue * price))
                            .animation(.snappy, value: sharesValue)
                    }

                    if let serverError {
                        Label(serverError, systemImage: "exclamationmark.triangle")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.bearish)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !holding.isEmpty {
                        Button(role: .destructive) {
                            save(shares: nil, avgCost: nil)
                        } label: {
                            Label("Remove position", systemImage: "trash")
                                .font(Theme.bodyEmphasis)
                                .foregroundStyle(Theme.bearish)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.bearish.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.97))
                        .disabled(isSaving)
                        .padding(.top, 4)
                    }
                }
                .padding(Theme.margin)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("\(stock.ticker) position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Theme.gold)
                    } else {
                        Button("Save") {
                            showErrors = true
                            guard isValid else { return }
                            save(shares: sharesValue, avgCost: costValue)
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .sensoryFeedback(.error, trigger: showErrors && !isValid)
        .onAppear { if holding.isEmpty { focused = .shares } }
    }

    private func save(shares: Double?, avgCost: Double?) {
        isSaving = true
        serverError = nil
        Task {
            let message = await store.updateHolding(for: stock, shares: shares, avgCost: avgCost)
            isSaving = false
            if let message { serverError = message } else { dismiss() }
        }
    }
}

/// Decimal text field with an optional currency prefix / unit suffix and an inline error.
private struct NumberField: View {
    let label: String
    let prefix: String?
    let suffix: String?
    let placeholder: String
    @Binding var text: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                if let prefix {
                    Text(prefix)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                }
                TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textTertiary))
                    .keyboardType(.decimalPad)
                    .foregroundStyle(Theme.textPrimary)
                if let suffix {
                    Text(suffix)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
            }
            .font(Theme.number(.title3))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .strokeBorder(error == nil ? Theme.stroke : Theme.bearish.opacity(0.7))
            )
            if let error {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.bearish)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: error)
        .accessibilityElement(children: .contain)
    }
}
