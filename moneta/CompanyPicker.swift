import SwiftUI

/// A company the user can pick, from the Top 20 or from search.
struct CompanyChoice: Identifiable, Hashable {
    let ticker: String
    let name: String
    let domain: String?
    let rank: Int?
    var logoURL: String? = nil
    var brandColor: String? = nil

    var id: String { ticker }

    init(_ company: Company) {
        ticker = company.ticker
        name = company.name
        domain = company.domain
        rank = company.rank
        logoURL = company.logoURL
        brandColor = company.brandColor
    }

    init(_ result: CompanySearchResult) {
        ticker = result.ticker.uppercased()
        name = result.name
        domain = result.domain
        rank = nil
    }
}

/// Row with rank, initials logo, name, ticker and a +/✓ toggle.
struct CompanyPickRow: View {
    let company: CompanyChoice
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                if let rank = company.rank {
                    Text("\(rank)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, alignment: .trailing)
                }
                CompanyLogo(ticker: company.ticker, logoURL: company.logoURL, brandColor: company.brandColor, size: .row)
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name)
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(company.ticker)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.gold : Color.white.opacity(0.06))
                    Image(systemName: isSelected ? "checkmark" : "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? Theme.background : Theme.gold)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 34, height: 34)
                .animation(.snappy(duration: 0.25), value: isSelected)
            }
            .card(padding: 12, border: isSelected ? Theme.gold.opacity(0.5) : nil)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Removes from your picks" : "Adds to your picks")
    }
}

/// Search field in the Moneta style.
struct SearchBar: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            field
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(Theme.stroke))
    }

    @ViewBuilder private var field: some View {
        let base = TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textTertiary))
            .foregroundStyle(Theme.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
        if let isFocused {
            base.focused(isFocused)
        } else {
            base
        }
    }
}

/// Sheet that searches all companies through the `search-companies` function.
struct CompanySearchSheet: View {
    @Binding var selection: [CompanyChoice]
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [CompanyChoice] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var tapCount = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SearchBar(placeholder: "Company name or ticker", text: $query, isFocused: $searchFocused)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if isSearching {
                            ProgressView().tint(Theme.gold).padding(.top, 32)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Theme.bearish)
                                .padding(.top, 32)
                        } else if results.isEmpty {
                            Text(query.trimmingCharacters(in: .whitespaces).count < 1
                                 ? "Search by company name or ticker, like “Spotify” or “SHOP”."
                                 : "No companies found for “\(query)”.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 32)
                                .padding(.horizontal, 24)
                        } else {
                            ForEach(results) { company in
                                CompanyPickRow(company: company, isSelected: isSelected(company)) {
                                    toggle(company)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Search companies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount)
        .task(id: query) { await search() }
        .onAppear { searchFocused = true }
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

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await MonetaAPI.searchCompanies(query: trimmed)
            guard !Task.isCancelled else { return }
            var seen = Set<String>()
            results = found.map(CompanyChoice.init).filter { seen.insert($0.ticker).inserted }
            // Show hits at once, then fill in logos from `companies`.
            let branding = await MonetaAPI.companyBranding(tickers: results.map(\.ticker))
            guard !Task.isCancelled, !branding.isEmpty else { return }
            results = results.map { choice in
                guard let brand = branding[choice.ticker] else { return choice }
                var updated = choice
                updated.logoURL = brand.logoURL
                updated.brandColor = brand.brandColor
                return updated
            }
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = "Search failed. \(error.localizedDescription)"
        }
    }
}
