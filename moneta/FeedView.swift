import SwiftUI

struct FeedView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSignal: Signal?
    @State private var showingAddStock = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                        header
                        stockChips
                        feedHeader
                        if let message = store.errorMessage {
                            ErrorBanner(message: message) { store.errorMessage = nil }
                        }
                        feed
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await store.pollNow()
                    await store.load()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedSignal) { signal in
                SignalDetailView(signal: signal, stock: store.stock(for: signal))
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Theme.background)
            }
            .sheet(isPresented: $showingAddStock) {
                AddStockView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Theme.background)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: store.alertCount)
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await store.load()
                    await store.startRealtime()
                }
            case .background:
                Task { await store.stopRealtime() }
            default:
                break
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Moneta")
                    .font(Theme.wordmark(size: 36))
                    .foregroundStyle(Theme.gold)
                Text("The web knows first. Now so do you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    Task { await store.pollNow() }
                } label: {
                    Group {
                        if store.isPolling {
                            ProgressView().tint(Theme.gold)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
                }
                .disabled(store.isPolling)
                .accessibilityLabel("Check for news now")

                Button {
                    showingAddStock = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.background)
                        .background(Theme.gold, in: Circle())
                }
                .accessibilityLabel("Add stock")
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 8)
    }

    private var stockChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    subtitle: "\(store.signals.count) signals",
                    isSelected: store.selectedStockID == nil
                ) {
                    withAnimation(.snappy) { store.selectedStockID = nil }
                }
                ForEach(store.stocks) { stock in
                    FilterChip(
                        title: stock.ticker,
                        subtitle: stock.name,
                        isSelected: store.selectedStockID == stock.id,
                        leading: AnyView(StockLogo(ticker: stock.ticker, logoURL: stock.logoURL, brandColor: stock.brandColor, size: 30))
                    ) {
                        withAnimation(.snappy) {
                            store.selectedStockID = store.selectedStockID == stock.id ? nil : stock.id
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    private var feedHeader: some View {
        @Bindable var store = store
        return HStack {
            LivePulse(isLive: store.isLive)
            Spacer()
            Menu {
                Picker("Minimum impact", selection: $store.minimumImpact) {
                    Text("Any impact").tag(1)
                    Text("Impact 3+").tag(3)
                    Text("Impact 4+").tag(4)
                    Text("Impact 5 only").tag(5)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(store.minimumImpact == 1 ? "Any impact" : "Impact \(store.minimumImpact)+")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.minimumImpact == 1 ? Theme.textSecondary : Theme.gold)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Theme.card, in: Capsule())
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var feed: some View {
        let signals = store.visibleSignals
        if signals.isEmpty {
            EmptyFeed(isLoading: store.isLoading, hasStocks: !store.stocks.isEmpty) {
                if store.stocks.isEmpty {
                    showingAddStock = true
                } else {
                    Task { await store.pollNow() }
                }
            }
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                LazyVStack(spacing: 12) {
                    ForEach(signals) { signal in
                        Button {
                            store.markSeen(signal)
                            selectedSignal = signal
                        } label: {
                            SignalCard(
                                signal: signal,
                                stock: store.stock(for: signal),
                                isLive: store.freshIds.contains(signal.id),
                                now: context.date
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(duration: 0.45, bounce: 0.15), value: signals.map(\.id))
            }
        }
    }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.bearish)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
            }
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

private struct EmptyFeed: View {
    let isLoading: Bool
    let hasStocks: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(Theme.gold)
                Text("Reading the web…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: hasStocks ? "waveform.path.ecg" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.gold)
                Text(hasStocks ? "No signals yet" : "Track your first stock")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(hasStocks
                     ? "Nothing matches this filter. Check the web now or widen the impact filter."
                     : "Add a ticker and Moneta starts watching its news, IR page, careers and pricing.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                Button(hasStocks ? "Check for news" : "Add stock", action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Theme.gold, in: Capsule())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .card()
    }
}
