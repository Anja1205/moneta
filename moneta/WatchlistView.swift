import SwiftUI

struct WatchlistView: View {
    @Environment(SignalStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showingAddStock = false

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let message = store.errorMessage {
                        ErrorBanner(message: message) { store.errorMessage = nil }
                    }
                    if store.stocks.isEmpty {
                        WatchlistEmptyState(isLoading: store.isLoading) { showingAddStock = true }
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVStack(spacing: 12) {
                                ForEach(store.stocks) { stock in
                                    let latest = store.latestSignal(for: stock)
                                    NavigationLink(value: stock) {
                                        StockCard(
                                            stock: stock,
                                            latest: latest,
                                            isFresh: latest.map { store.freshIds.contains($0.id) } ?? false,
                                            now: context.date
                                        )
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .contextMenu {
                                        if let latest {
                                            Button("Open latest signal", systemImage: "doc.text") {
                                                path.append(latest)
                                            }
                                        }
                                    }
                                }
                            }
                            .animation(.spring(duration: 0.4, bounce: 0.15), value: store.stocks.map(\.id))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                await store.pollNow()
                await store.load()
            }
            .toolbar {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarLeading) { wordmark }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { wordmark }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    LivePill(isLive: store.isLive)
                    Button {
                        showingAddStock = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                    .accessibilityLabel("Add stock")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Stock.self) { stock in
                StockDetailView(stock: stock)
            }
            .navigationDestination(for: Signal.self) { signal in
                SignalDetailView(signal: signal, stock: store.stock(for: signal))
                    .toolbarBackground(Theme.background, for: .navigationBar)
            }
        }
        .sheet(isPresented: $showingAddStock) {
            AddStockView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }

    private var wordmark: some View {
        Text("Moneta")
            .font(Theme.wordmark(size: 28))
            .foregroundStyle(Theme.gold)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - StockCard

struct StockCard: View {
    let stock: Stock
    let latest: Signal?
    let isFresh: Bool
    let now: Date

    private var brand: Color { stock.brandColor.map(Color.init(hex:)) ?? Theme.gold }
    private var directionColor: Color { latest.map { Theme.color(for: $0.direction) } ?? Theme.neutral }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StockLogo(stock: stock, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(directionColor)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(latest?.direction.label ?? "No signal")
                    Text(stock.ticker)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(stock.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(latest.map { RelativeTime.string(for: $0.detectedDate, now: now) } ?? "")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isFresh ? Theme.gold : Theme.textTertiary)
                }

                Text(latest?.why ?? "No signals yet. Moneta is watching the web for \(stock.name).")
                    .font(.subheadline)
                    .foregroundStyle(latest == nil ? Theme.textTertiary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 16)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .card(highlighted: isFresh)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.cornerRadius, bottomLeadingRadius: Theme.cornerRadius, style: .continuous)
                .fill(brand)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

private struct WatchlistEmptyState: View {
    let isLoading: Bool
    let addStock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(Theme.gold)
                Text("Loading your watchlist…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "binoculars")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.gold)
                Text("Your watchlist is empty")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Add a stock and Moneta watches its news, investor relations, careers and pricing pages for you.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                Button(action: addStock) {
                    Label("Add stock", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Theme.gold, in: Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .card()
    }
}
