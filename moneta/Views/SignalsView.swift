import SwiftUI

/// "Important" (impact 3+) or every signal. Shared by the feed and the stock timeline.
enum ImpactFilter: String, CaseIterable, Identifiable {
    case important = "Important", all = "All"
    var id: String { rawValue }

    func keeps(_ signal: Signal) -> Bool { self == .all || signal.impact.isImportant }
}

/// Direction chips on the feed.
enum DirectionFilter: String, CaseIterable, Identifiable {
    case all = "All", bullish = "Bullish", bearish = "Bearish"
    var id: String { rawValue }

    func keeps(_ signal: Signal) -> Bool {
        switch self {
        case .all: true
        case .bullish: signal.direction == .bullish
        case .bearish: signal.direction == .bearish
        }
    }
}

/// Every signal across watched stocks, newest first.
struct SignalsView: View {
    @Environment(MarketStore.self) private var store
    @AppStorage("feed.impactFilter") private var filter: ImpactFilter = .important
    @AppStorage("feed.directionFilter") private var direction: DirectionFilter = .all

    private var visible: [Signal] {
        store.signals.filter { filter.keeps($0) && direction.keeps($0) }
    }

    /// "No important bullish news right now — Moneta is watching."
    private var emptyText: String {
        let kind = [filter == .important ? "important" : nil, direction == .all ? nil : direction.rawValue.lowercased()]
            .compactMap { $0 }.joined(separator: " ")
        return kind.isEmpty ? "No news right now — Moneta is watching." : "No \(kind) news right now — Moneta is watching."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.spacing) {
                    GlassSegmented(options: ImpactFilter.allCases, selection: $filter, title: \.rawValue,
                                   accessibilityLabel: "Show")
                    DirectionChips(selection: $direction)
                        .padding(.bottom, 6)

                    if !store.isLoaded {
                        ForEach(0..<4, id: \.self) { _ in ShimmerRow() }
                    } else if visible.isEmpty {
                        ContentUnavailableView(
                            "Nothing here yet", systemImage: "eye",
                            description: Text(emptyText)
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
            .refreshable { await store.refresh(fetchNews: true) }
            .monetaScreen()
            .navigationTitle("Signals")
            .monetaDestinations()
        }
    }
}

/// Small capsule chips: All / Bullish / Bearish.
struct DirectionChips: View {
    @Binding var selection: DirectionFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DirectionFilter.allCases) { option in
                let isSelected = option == selection
                let color: Color = switch option {
                case .all: Palette.text
                case .bullish: Palette.up
                case .bearish: Palette.down
                }
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    HStack(spacing: 4) {
                        if option != .all {
                            Image(systemName: option == .bullish ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        Text(option.rawValue)
                    }
                    .font(.mCaption)
                    .foregroundStyle(isSelected ? Palette.background : color)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(isSelected ? color : Palette.tint(color), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Direction")
    }
}

#Preview {
    SignalsView()
        .environment(MarketStore.preview())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
