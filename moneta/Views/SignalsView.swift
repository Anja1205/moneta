import SwiftUI

/// Every signal across watched stocks, newest first.
struct SignalsView: View {
    @Environment(MonetaStore.self) private var store
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", high = "High", medium = "Medium", low = "Low"
        var id: String { rawValue }
        var impact: Impact? {
            switch self {
            case .all: nil
            case .high: .high
            case .medium: .medium
            case .low: .low
            }
        }
    }

    private var visible: [Signal] {
        store.signals.filter { filter.impact == nil || $0.impact == filter.impact }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.spacing) {
                    GlassSegmented(options: Filter.allCases, selection: $filter, title: \.rawValue,
                                   accessibilityLabel: "Filter by impact")
                        .padding(.bottom, 6)

                    if visible.isEmpty {
                        ContentUnavailableView(
                            "No signals", systemImage: "waveform.path.ecg",
                            description: Text(filter == .all ? "New signals appear here the moment Moneta spots them." : "No \(filter.rawValue.lowercased())-impact signals today.")
                        )
                        .padding(.top, 40)
                    }

                    LazyVStack(spacing: Metrics.spacing) {
                        ForEach(visible) { signal in
                            NavigationLink(value: Route.signal(signal.id)) {
                                SignalTimelineCard(
                                    signal: signal,
                                    number: store.pinNumber(for: signal),
                                    reaction: store.reaction(to: signal),
                                    company: store.company(signal.ticker),
                                    isFresh: store.freshIDs.contains(signal.id),
                                    isMuted: store.isMuted(signal)
                                )
                            }
                            .buttonStyle(PressableStyle())
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.75), value: visible.map(\.id))
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .monetaScreen()
            .navigationTitle("Signals")
            .monetaDestinations()
        }
    }
}

#Preview {
    SignalsView()
        .environment(MonetaStore.preview())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
