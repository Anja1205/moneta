import SwiftUI

private struct Row: Identifiable, Hashable {
    let ticker: String
    let name: String
    let domain: String?
    let isLiveWeb: Bool
    var logoURL: String? = nil
    var brandColor: String? = nil
    var id: String { ticker }
}

private enum AddState { case adding, added }

/// Sheet for finding a company and adding it to the watchlist.
struct StockSearchView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var popular: [Row] = []
    @State private var results: [Row] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var popularError: String?
    @State private var addStates: [String: AddState] = [:]
    @State private var rowErrors: [String: String] = [:]
    @State private var retryToken = 0
    @State private var addedTrigger = 0
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SearchBar(placeholder: "Search company or ticker", text: $query, isFocused: $searchFocused)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sensoryFeedback(.success, trigger: addedTrigger)
        // Re-runs (and cancels the previous run) whenever the query or a retry changes.
        .task(id: "\(query)|\(retryToken)") { await search() }
        .task { await loadPopular() }
        .onAppear { searchFocused = true }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            sectionTitle("Popular")
            if let popularError {
                ErrorState(message: popularError) { Task { await loadPopular() } }
            } else if popular.isEmpty {
                ProgressView().tint(Theme.gold).frame(maxWidth: .infinity).padding(.top, 32)
            } else {
                rows(popular)
            }
        } else if isSearching && results.isEmpty {
            ProgressView().tint(Theme.gold).frame(maxWidth: .infinity).padding(.top, 32)
        } else if let searchError {
            ErrorState(message: searchError) { retryToken += 1 }
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.gold)
                Text("No companies found")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Try the full company name or its ticker.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            sectionTitle("Results")
            rows(results)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        SectionLabel(text)
            .padding(.top, 4)
            .padding(.leading, 4)
    }

    private func rows(_ list: [Row]) -> some View {
        ForEach(list) { row in
            VStack(alignment: .leading, spacing: 4) {
                ResultRow(row: row, state: state(for: row)) { add(row) }
                if let message = rowErrors[row.ticker] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.bearish)
                        .padding(.horizontal, 14)
                }
            }
        }
    }

    private func state(for row: Row) -> AddState? {
        if let state = addStates[row.ticker] { return state }
        return store.isWatching(ticker: row.ticker) ? .added : nil
    }

    // MARK: Actions

    private func add(_ row: Row) {
        guard state(for: row) == nil else { return }
        addStates[row.ticker] = .adding
        rowErrors[row.ticker] = nil
        Task {
            if let error = await store.addStock(ticker: row.ticker, name: row.name, domain: row.domain) {
                addStates[row.ticker] = nil
                rowErrors[row.ticker] = error
            } else {
                addStates[row.ticker] = .added
                addedTrigger += 1
            }
        }
    }

    private func search() async {
        let text = trimmedQuery
        searchError = nil
        guard !text.isEmpty else {
            results = []
            isSearching = false
            return
        }
        // Debounce: a new keystroke cancels this task before the request goes out.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { if !Task.isCancelled { isSearching = false } }
        do {
            let found = try await MonetaAPI.searchCompanies(query: text)
            guard !Task.isCancelled else { return }
            var seen = Set<String>()
            results = found.compactMap { hit in
                let ticker = hit.ticker.uppercased()
                guard seen.insert(ticker).inserted else { return nil }
                return Row(ticker: ticker, name: hit.name, domain: hit.domain,
                           isLiveWeb: hit.source?.lowercased() == "context.dev")
            }
            // Show hits at once, then fill in logos from `companies`.
            let branding = await MonetaAPI.companyBranding(tickers: results.map(\.ticker))
            guard !Task.isCancelled, !branding.isEmpty else { return }
            results = results.map { row in
                guard let brand = branding[row.ticker] else { return row }
                var updated = row
                updated.logoURL = brand.logoURL
                updated.brandColor = brand.brandColor
                return updated
            }
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = "Search failed. \(error.localizedDescription)"
        }
    }

    private func loadPopular() async {
        popularError = nil
        do {
            popular = try await MonetaAPI.featuredCompanies().map {
                Row(ticker: $0.ticker.uppercased(), name: $0.name, domain: $0.domain, isLiveWeb: false,
                    logoURL: $0.logoURL, brandColor: $0.brandColor)
            }
        } catch {
            popularError = "Couldn’t load popular companies. \(error.localizedDescription)"
        }
    }
}

// MARK: - Pieces

private struct ResultRow: View {
    let row: Row
    let state: AddState?
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CompanyLogo(ticker: row.ticker, logoURL: row.logoURL, brandColor: row.brandColor, size: .row)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(row.ticker)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                    if row.isLiveWeb {
                        Text("Live web")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.gold)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.gold.opacity(0.14), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 8)
            Button(action: add) {
                ZStack {
                    Circle().fill(state == .added ? Theme.gold : Color.white.opacity(0.06))
                    switch state {
                    case .adding:
                        ProgressView().tint(Theme.gold).controlSize(.small)
                    case .added:
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.background)
                            .transition(.scale.combined(with: .opacity))
                    case nil:
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .frame(width: 36, height: 36)
                .animation(.snappy(duration: 0.25), value: state)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88))
            .disabled(state != nil)
            .accessibilityLabel(state == .added ? "Watching \(row.ticker)" : "Add \(row.ticker)")
        }
        .card(padding: 12, border: state == .added ? Theme.gold.opacity(0.5) : nil)
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.bearish)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Button("Try again", action: retry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
