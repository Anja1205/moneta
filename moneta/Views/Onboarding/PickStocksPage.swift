import SwiftUI

/// Onboarding page 2: pick companies from the Top 20 (or search for more).
struct PickStocksPage: View {
    @Bindable var selection: OnboardingSelection
    let onContinue: () -> Void

    private enum LoadState { case loading, loaded, failed(String) }

    @State private var companies: [Company] = []
    @State private var state: LoadState = .loading
    @State private var query = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    private var filtered: [Company] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return companies }
        return companies.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.ticker.localizedCaseInsensitiveContains(q)
        }
    }

    /// Picked in the search sheet but not in the Top 20.
    private var extraPicks: [Company] {
        selection.companies.filter { pick in !companies.contains { $0.ticker == pick.ticker } }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.spacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What do you invest in?")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Brand.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("Tap + on the companies you want Moneta to watch.")
                            .font(.callout)
                            .foregroundStyle(Brand.muted)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    BrandSearchField(prompt: "Search the Top 20", text: $query, focus: $searchFocused)

                    content

                    Button {
                        showSearch = true
                    } label: {
                        Label("Search more companies", systemImage: "magnifyingglass")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Brand.gold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Brand.margin)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showSearch) {
            StockSearchView(mode: .onboarding(selection))
        }
        .task { if companies.isEmpty { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ForEach(0..<7, id: \.self) { _ in ShimmerRow() }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await load() } }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.gold)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .brandCard()
        case .loaded:
            if !extraPicks.isEmpty && query.isEmpty {
                ForEach(extraPicks) { company in
                    row(company, rank: nil)
                }
            }
            if filtered.isEmpty {
                Text("No matches in the Top 20. Try searching more companies.")
                    .font(.callout)
                    .foregroundStyle(Brand.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
            } else {
                ForEach(filtered) { company in
                    row(company, rank: company.rank ?? (companies.firstIndex(of: company).map { $0 + 1 }))
                }
            }
        }
    }

    private func row(_ company: Company, rank: Int?) -> some View {
        CompanyPickRow(company: company, rank: rank, isSelected: selection.contains(company.ticker)) {
            selection.toggle(company)
        }
    }

    private var bottomBar: some View {
        let count = selection.count
        return PrimaryButton(count == 1 ? "Watch 1 stock" : "Watch \(count) stocks", action: onContinue)
            .disabled(count == 0)
            .padding(.horizontal, Brand.margin)
            .padding(.top, 36)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    stops: [.init(color: Brand.background.opacity(0), location: 0),
                            .init(color: Brand.background, location: 0.45)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            )
            .contentTransition(.numericText())
            .animation(.snappy, value: count)
    }

    private func load() async {
        state = .loading
        do {
            companies = try await MonetaAPI.featuredCompanies()
            withAnimation(.easeOut(duration: 0.25)) { state = .loaded }
        } catch {
            state = .failed("Couldn’t load companies. Check your connection.")
        }
    }
}

/// Rank, logo, name and ticker, with a +/✓ toggle.
struct CompanyPickRow: View {
    let company: Company
    let rank: Int?
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.number(15))
                        .monospacedDigit()
                        .foregroundStyle(Brand.muted)
                        .frame(minWidth: 22)
                }
                CompanyLogo(company: company, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                    Text(company.ticker)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 8)
                ListPriceLabel(company: company)
                AddToggleIcon(isOn: isSelected)
            }
            .padding(12)
            .brandCard()
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(Brand.gold.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .sensoryFeedback(.impact(weight: .light), trigger: isSelected)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(company.name), \(company.ticker)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Removes it from your picks" : "Adds it to your picks")
    }
}
