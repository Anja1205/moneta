import SwiftUI

/// Shown after sign-up while `profile.onboarded == false`.
struct OnboardingView: View {
    @Environment(AuthService.self) private var auth

    private enum Page: Int, CaseIterable { case welcome, pick, setup }

    @State private var page: Page = .welcome
    @State private var selection: [CompanyChoice] = []

    var body: some View {
        VStack(spacing: 0) {
            ProgressSegments(current: page.rawValue, total: Page.allCases.count)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            ZStack {
                switch page {
                case .welcome:
                    WelcomePage { go(to: .pick) }
                        .transition(pageTransition)
                case .pick:
                    PickStocksPage(selection: $selection,
                                   back: { go(to: .welcome) },
                                   next: { go(to: .setup) })
                        .transition(pageTransition)
                case .setup:
                    SetupPage(picks: selection)
                        .transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func go(to next: Page) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { page = next }
    }
}

// MARK: - Progress

private struct ProgressSegments: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.gold : Color.white.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let next: () -> Void

    var body: some View {
        // Scrolls when the content is taller than the screen (iPhone SE, large text); the button stays pinned.
        ScrollView {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 18) {
                Wordmark(size: 56)
                    .padding(.vertical, 8)
                Text("Moneta watches the live web around your stocks and warns you before the market moves.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(symbol: "newspaper", text: "Breaking news, as it happens")
                FeatureRow(symbol: "sparkles", text: "AI explains why it matters")
                FeatureRow(symbol: "bell.badge", text: "Alerts on your lock screen")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 20)
            .padding(.top, 32)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .containerRelativeFrame(.vertical) { height, _ in height }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Get started", action: next)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(Theme.background)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.gold)
                .frame(width: 36, height: 36)
                .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 2: Pick stocks

private struct PickStocksPage: View {
    @Binding var selection: [CompanyChoice]
    let back: () -> Void
    let next: () -> Void

    @State private var featured: [CompanyChoice] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSearch = false
    @State private var tapCount = 0

    /// Top 20 filtered locally, plus picks from search that aren't in the Top 20.
    private var rows: [CompanyChoice] {
        let extras = selection.filter { pick in !featured.contains { $0.ticker == pick.ticker } }
        let all = featured + extras
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.ticker.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What do you invest in?")
                        .font(Theme.title)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tap + on the companies you want Moneta to watch.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                SearchBar(placeholder: "Filter the top 20", text: $query)

                if isLoading {
                    ProgressView()
                        .tint(Theme.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.bearish)
                        Button("Try again") { Task { await load() } }
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { company in
                            CompanyPickRow(company: company, isSelected: isSelected(company)) {
                                toggle(company)
                            }
                        }
                        if rows.isEmpty {
                            Text("No match in the top 20.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 16)
                        }
                    }
                }

                Button {
                    showingSearch = true
                } label: {
                    Label("Search more companies", systemImage: "magnifyingglass")
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                title: selection.isEmpty ? "Pick at least one" : "Watch \(selection.count) \(selection.count == 1 ? "stock" : "stocks")",
                isEnabled: !selection.isEmpty,
                action: next
            )
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                               startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
        }
        .sensoryFeedback(.selection, trigger: tapCount)
        .sheet(isPresented: $showingSearch) {
            CompanySearchSheet(selection: $selection)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .task { if featured.isEmpty { await load() } }
    }

    private func isSelected(_ company: CompanyChoice) -> Bool {
        selection.contains { $0.ticker == company.ticker }
    }

    private func toggle(_ company: CompanyChoice) {
        tapCount += 1
        if let index = selection.firstIndex(where: { $0.ticker == company.ticker }) {
            selection.remove(at: index)
        } else {
            selection.append(company)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            featured = try await MonetaAPI.featuredCompanies().map(CompanyChoice.init)
        } catch {
            errorMessage = "Couldn’t load companies. \(error.localizedDescription)"
        }
    }
}

// MARK: - Page 3: Setting up

private struct SetupPage: View {
    let picks: [CompanyChoice]
    @Environment(AuthService.self) private var auth

    private enum Status { case waiting, working, done, failed }

    @State private var status: [String: Status] = [:]
    @State private var allSet = false
    @State private var successTrigger = 0

    private var finishedCount: Int {
        status.values.filter { $0 == .done || $0 == .failed }.count
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)

            ZStack {
                if allSet {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Theme.gold)
                            .symbolEffect(.bounce, value: allSet)
                        Text("You’re all set")
                            .font(Theme.wordmark(size: 30))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Moneta is watching the web for you.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    VStack(spacing: 8) {
                        Text("Setting up")
                            .font(Theme.wordmark(size: 30))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Reading the live web for \(picks.count) \(picks.count == 1 ? "company" : "companies")…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        ProgressView(value: Double(finishedCount), total: Double(max(picks.count, 1)))
                            .tint(Theme.gold)
                            .padding(.top, 8)
                            .padding(.horizontal, 40)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: allSet)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(picks) { pick in
                        ChecklistRow(ticker: pick.ticker, status: status[pick.ticker] ?? .waiting)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 360)
            .card()

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .sensoryFeedback(.success, trigger: successTrigger)
        .task { await run() }
    }

    private struct ChecklistRow: View {
        let ticker: String
        let status: Status

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    switch status {
                    case .waiting:
                        Circle().strokeBorder(Theme.textTertiary, lineWidth: 1.5).frame(width: 18, height: 18)
                    case .working:
                        ProgressView().tint(Theme.gold).controlSize(.small)
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.bullish)
                            .transition(.scale.combined(with: .opacity))
                    case .failed:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bearish)
                    }
                }
                .frame(width: 22, height: 22)

                Text(label)
                    .font(.subheadline.weight(status == .working ? .semibold : .regular))
                    .foregroundStyle(status == .waiting ? Theme.textTertiary : Theme.textPrimary)
                Spacer()
            }
            .animation(.snappy, value: status)
            .accessibilityElement(children: .combine)
        }

        private var label: String {
            switch status {
            case .waiting: "Waiting for \(ticker)"
            case .working: "Adding \(ticker)…"
            case .done: "Watching \(ticker)"
            case .failed: "Couldn’t add \(ticker)"
            }
        }
    }

    private func run() async {
        guard status.isEmpty else { return }
        status = Dictionary(uniqueKeysWithValues: picks.map { ($0.ticker, .waiting) })

        // add-stock for every pick, at most 4 at a time.
        await withTaskGroup(of: (String, Bool).self) { group in
            var next = 0
            func start(_ pick: CompanyChoice) {
                status[pick.ticker] = .working
                group.addTask {
                    do {
                        _ = try await MonetaAPI.addStock(ticker: pick.ticker, name: pick.name, domain: pick.domain)
                        return (pick.ticker, true)
                    } catch {
                        return (pick.ticker, false)
                    }
                }
            }
            while next < min(4, picks.count) {
                start(picks[next])
                next += 1
            }
            for await (ticker, ok) in group {
                status[ticker] = ok ? .done : .failed
                if next < picks.count {
                    start(picks[next])
                    next += 1
                }
            }
        }

        allSet = true
        successTrigger += 1
        try? await Task.sleep(for: .seconds(1.4))
        await AlertService.shared.requestPermission()
        await auth.completeOnboarding()
    }
}

#Preview {
    OnboardingView()
        .environment(AuthService())
}
