import Charts
import SwiftUI

struct StockDetailView: View {
    let stock: Stock
    @Environment(SignalStore.self) private var store

    /// Live copy so Realtime stock updates show here too.
    private var current: Stock { store.stocks.first { $0.id == stock.id } ?? stock }
    private var signals: [Signal] { store.signals(for: stock) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SignalChart(signals: signals)
                timeline
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
        .navigationTitle(current.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LivePill(isLive: store.isLive)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            StockLogo(stock: current, size: 88)
            Text(current.ticker)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(current.name)
                .font(Theme.wordmark(size: 20))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var timeline: some View {
        Text("Timeline")
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)

        if signals.isEmpty {
            Text("No signals yet. Pull down to check the web now.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .card()
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                LazyVStack(spacing: 12) {
                    ForEach(signals) { signal in
                        NavigationLink(value: signal) {
                            SignalRow(
                                signal: signal,
                                isFresh: store.freshIds.contains(signal.id),
                                now: context.date
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: signals.map(\.id))
            }
        }
    }
}

// MARK: - Chart

private struct SignalChart: View {
    let signals: [Signal]

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Int
        let direction: Direction
    }

    private var points: [Point] {
        signals.compactMap { signal in
            guard let date = signal.publishedDate ?? signal.detectedDate else { return nil }
            let value: Int
            switch signal.direction {
            case .bullish: value = signal.clampedImpact
            case .bearish: value = -signal.clampedImpact
            case .neutral: value = 0
            }
            return Point(id: signal.id, date: date, value: value, direction: signal.direction)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signal pressure")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            if points.isEmpty {
                Text("The chart fills in as signals arrive.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.white.opacity(0.15))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    ForEach(points) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Impact", point.value),
                            width: .fixed(6)
                        )
                        .foregroundStyle(Theme.color(for: point.direction))
                        .cornerRadius(2)

                        // Neutral signals have zero height; mark them so they stay visible.
                        if point.value == 0 {
                            PointMark(x: .value("Date", point.date), y: .value("Impact", 0))
                                .symbolSize(28)
                                .foregroundStyle(Theme.neutral)
                        }
                    }
                }
                .chartYScale(domain: -5...5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [-5, 0, 5]) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            switch value.as(Int.self) {
                            case 5: Text("Bullish").foregroundStyle(Theme.bullish)
                            case -5: Text("Bearish").foregroundStyle(Theme.bearish)
                            default: Text("")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Signals over time, bullish above the line, bearish below")
            }
        }
        .padding(16)
        .card()
    }
}
