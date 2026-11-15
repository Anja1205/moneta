import SwiftUI
import UserNotifications

/// Adds each pick with `add-stock` (at most 4 at once).
@Observable
final class WatchlistSetup {
    enum Status { case working, done, failed }

    struct Item: Identifiable {
        let company: Company
        var status: Status = .working
        var id: String { company.ticker }
    }

    private(set) var items: [Item]
    private static let maxParallel = 4

    init(companies: [Company]) {
        items = companies.map { Item(company: $0) }
    }

    var isFinished: Bool { !items.contains { $0.status == .working } }
    var failedCount: Int { items.filter { $0.status == .failed }.count }

    func run() async {
        await add(items.map(\.company))
    }

    func retry(_ ticker: String) async {
        guard let item = items.first(where: { $0.id == ticker }), item.status == .failed else { return }
        await add([item.company])
    }

    private func add(_ companies: [Company]) async {
        for company in companies { set(company.ticker, .working) }
        await withTaskGroup(of: (String, Bool).self) { group in
            var queue = companies.makeIterator()
            for _ in 0..<Self.maxParallel {
                guard let company = queue.next() else { break }
                group.addTask { await Self.addStock(company) }
            }
            while let (ticker, ok) = await group.next() {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { set(ticker, ok ? .done : .failed) }
                if let company = queue.next() {
                    group.addTask { await Self.addStock(company) }
                }
            }
        }
    }

    private nonisolated static func addStock(_ company: Company) async -> (String, Bool) {
        do {
            try await MonetaAPI.addStock(company)
            return (company.ticker, true)
        } catch {
            return (company.ticker, false)
        }
    }

    private func set(_ ticker: String, _ status: Status) {
        guard let index = items.firstIndex(where: { $0.id == ticker }) else { return }
        items[index].status = status
    }
}

/// Onboarding page 3: progress per company, then "You're all set".
struct SetupPage: View {
    @Binding var isWorking: Bool

    @Environment(AuthService.self) private var auth
    @State private var setup: WatchlistSetup
    @State private var showDone = false
    @State private var askedNotifications = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(companies: [Company], isWorking: Binding<Bool>) {
        _isWorking = isWorking
        _setup = State(initialValue: WatchlistSetup(companies: companies))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.spacing) {
                    if showDone {
                        allSet
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        Text("Setting up your watchlist")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Brand.text)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                            .transition(.opacity)
                    }

                    // When everything worked the rows give way to the success state.
                    ForEach(setup.items.filter { !showDone || $0.status != .done }) { item in
                        SetupRow(item: item) {
                            Task { await setup.retry(item.id) }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, Brand.margin)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            if showDone {
                footer
                    .padding(.horizontal, Brand.margin)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: showDone) { _, done in done }
        .task {
            isWorking = true
            await setup.run()
            isWorking = false
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showDone = true }
            try? await Task.sleep(for: .milliseconds(700))
            await requestNotifications()
        }
        .onChange(of: setup.isFinished) { _, finished in
            // A retry is running again after the first pass.
            if showDone { isWorking = !finished }
        }
    }

    private var allSet: some View {
        VStack(spacing: 14) {
            CheckBadge(animate: !reduceMotion)
                .padding(.top, 48)
            Text("You’re all set")
                .font(.title.weight(.bold))
                .foregroundStyle(Brand.text)
                .accessibilityAddTraits(.isHeader)
            Text("Moneta is now watching the web for you.")
                .font(.callout)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if setup.failedCount > 0 {
                Text("\(setup.failedCount) couldn’t be added — you can add them later")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
            }
            if let error = auth.errorMessage {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Brand.bearish)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton("Open Moneta", isLoading: auth.isLoading) {
                Task { await auth.completeOnboarding() }
            }
            .disabled(!askedNotifications || !setup.isFinished)
        }
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        withAnimation(.easeOut(duration: 0.2)) { askedNotifications = true }
    }
}

private struct SetupRow: View {
    let item: WatchlistSetup.Item
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CompanyLogo(company: item.company, size: 28)
            Text("Watching \(item.company.ticker)")
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.text)
            Spacer()
            status
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .brandCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .working:
            ProgressView()
                .tint(Brand.muted)
                .accessibilityLabel("Adding")
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Brand.bullish)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Added")
        case .failed:
            Button(action: retry) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Brand.bearish)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Couldn’t add \(item.company.ticker). Try again")
        }
    }
}

/// Big gold checkmark that scales in.
private struct CheckBadge: View {
    let animate: Bool
    @State private var shown = false

    var body: some View {
        ZStack {
            GoldGlow(size: 220, intensity: 0.35, period: 2.4)
            Circle()
                .fill(Brand.gold)
                .frame(width: 96, height: 96)
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(height: 140)
        .scaleEffect(shown ? 1 : 0.3)
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(true)
        .onAppear {
            if animate {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true }
            } else {
                shown = true
            }
        }
    }
}
