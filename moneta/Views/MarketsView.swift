import SwiftUI

/// Top 30 (`companies` rank 1–30) with live prices. A watched stock opens its detail;
/// any other opens a sheet with "Watch".
struct MarketsView: View {
    @Environment(MarketStore.self) private var store
    @State private var path = NavigationPath()
    @State private var preview: MarketCompany?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    switch store.marketsState {
                    case .loading where store.markets.isEmpty:
                        ForEach(0..<10, id: \.self) { _ in ShimmerRow() }
                    case .failed(let message) where store.markets.isEmpty:
                        ContentUnavailableView {
                            Label("Top 30 unavailable", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Try again") { Task { await store.loadMarkets() } }
                                .tint(Palette.amber)
                        }
                        .padding(.top, 40)
                    default:
                        ForEach(store.markets) { company in
                            Button {
                                if store.isWatching(company.ticker) {
                                    path.append(Route.stock(company.ticker))
                                } else {
                                    preview = company
                                }
                            } label: {
                                MarketRow(company: company, isWatching: store.isWatching(company.ticker))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await store.loadMarkets() }
            .monetaScreen()
            .navigationTitle("Markets")
            .monetaDestinations()
            .sheet(item: $preview) { company in
                WatchSheet(company: company)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Rank, logo, name, price and today's change.
private struct MarketRow: View {
    let company: MarketCompany
    let isWatching: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(company.rank.map(String.init) ?? "–")
                .font(.number(14))
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .frame(minWidth: 22)
            CompanyMark(company: company.company, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(company.name)
                        .font(.mBodyStrong)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if isWatching {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.amber)
                            .accessibilityLabel("Watching")
                    }
                }
                Text(company.ticker)
                    .font(.mFootnote)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let price = company.price {
                    Text(Fmt.price(price, currency: company.currency ?? "USD"))
                        .font(.mBodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText(value: price))
                        .animation(.snappy, value: price)
                } else {
                    Text("—").font(.mBodyStrong).foregroundStyle(Palette.muted)
                }
                if let change = company.changeFraction {
                    ChangeCapsule(fraction: change)
                }
            }
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A Top 30 company you don't watch yet: price and a "Watch" button (add-stock).
private struct WatchSheet: View {
    let company: MarketCompany
    @Environment(MarketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                CompanyMark(company: company.company, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name)
                        .font(.mTitle2)
                        .foregroundStyle(Palette.text)
                    Text(company.ticker + (company.rank.map { " · #\($0) in the Top 30" } ?? ""))
                        .font(.mFootnote)
                        .foregroundStyle(Palette.secondary)
                }
            }
            if let price = company.price {
                HStack(alignment: .center, spacing: 10) {
                    Text(Fmt.price(price, currency: company.currency ?? "USD"))
                        .font(.moneta(size: 32, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                    if let change = company.changeFraction { ChangeCapsule(fraction: change, large: true) }
                }
            }
            Text("Watch \(company.name) and Moneta warns you when something on the web could move it.")
                .font(.mCallout)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PrimaryButton("Watch \(company.ticker)", isLoading: isAdding) {
                Task {
                    isAdding = true
                    await store.addStock(company.company, settings: store.defaultSettings)
                    isAdding = false
                    dismiss()
                }
            }
        }
        .padding(Metrics.margin)
        .padding(.top, 12)
        .presentationBackground(Palette.background)
    }
}

#Preview {
    MarketsView()
        .environment(MarketStore.preview())
        .preferredColorScheme(.dark)
}
