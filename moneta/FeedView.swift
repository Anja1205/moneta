import SwiftUI

struct FeedView: View {
    @Environment(SignalStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let message = store.errorMessage {
                        ErrorBanner(message: message) { store.errorMessage = nil }
                    }
                    if store.signals.isEmpty {
                        WatchingEmptyState(isLoading: store.isLoading)
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVStack(spacing: 12) {
                                ForEach(store.signals) { signal in
                                    NavigationLink(value: signal) {
                                        SignalRow(
                                            signal: signal,
                                            stock: store.stock(for: signal),
                                            isFresh: store.freshIds.contains(signal.id),
                                            now: context.date
                                        )
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .transition(.signalInsert)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.signalSpring, value: store.signals.map(\.id))
                .animation(.easeOut(duration: 0.3), value: store.freshIds)
            }
            .scrollIndicators(.hidden)
            .demoScrollAnchor()
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                await store.refreshAll()
                await store.load()
            }
            .navigationTitle("Live Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LivePill(isLive: store.isLive)
                }
            }
            .navigationDestination(for: Signal.self) { signal in
                SignalDetailView(signal: signal, stock: store.stock(for: signal))
                    .toolbarBackground(Theme.background, for: .navigationBar)
            }
        }
    }
}

// MARK: - SignalRow

struct SignalRow: View {
    let signal: Signal
    /// Shows the company logo when set. Leave nil where the stock is already obvious (its detail screen).
    var stock: Stock? = nil
    let isFresh: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let stock {
                    CompanyLogo(stock: stock, size: .row)
                }
                Text(signal.ticker)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                DirectionBadge(direction: signal.direction)
                Spacer(minLength: 4)
                Text(RelativeTime.string(for: signal.detectedDate, now: now))
                    .font(Theme.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isFresh ? Theme.gold : Theme.textTertiary)
            }

            Text(signal.why)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                SourceChip(kind: signal.sourceKind, sourceName: signal.sourceName)
                Spacer(minLength: 4)
                ImpactMeter(impact: signal.clampedImpact, direction: signal.direction)
            }
        }
        .card(highlighted: isFresh)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

private struct WatchingEmptyState: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.gold)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
            Text("Watching the web…")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(isLoading
                 ? "Loading signals."
                 : "New signals land here the moment Moneta spots them. Pull down to check now.")
                .font(Theme.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .card()
    }
}

// MARK: - Motion

extension Animation {
    /// New signals spring into lists.
    static let signalSpring = Animation.spring(response: 0.5, dampingFraction: 0.75)
}

extension AnyTransition {
    /// A new signal drops in from the top with a slight scale; removals fade.
    static let signalInsert = AnyTransition.asymmetric(
        insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
        removal: .opacity
    )
}
