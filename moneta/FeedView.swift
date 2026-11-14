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
                                            isFresh: store.freshIds.contains(signal.id),
                                            now: context.date
                                        )
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: store.signals.map(\.id))
                .animation(.easeOut(duration: 0.3), value: store.freshIds)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                await store.pollNow()
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
    let isFresh: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(signal.ticker)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                DirectionBadge(direction: signal.direction)
                Spacer(minLength: 4)
                Text(RelativeTime.string(for: signal.detectedDate, now: now))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isFresh ? Theme.gold : Theme.textTertiary)
            }

            Text(signal.why)
                .font(.subheadline)
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
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isFresh ? Theme.gold : Theme.stroke, lineWidth: isFresh ? 1.5 : 1)
        )
        .shadow(color: isFresh ? Theme.gold.opacity(0.25) : .clear, radius: 12)
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
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(isLoading
                 ? "Loading signals."
                 : "New signals land here the moment Moneta spots them. Pull down to check now.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .card()
    }
}
