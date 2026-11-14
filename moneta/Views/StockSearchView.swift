import SwiftUI

/// Search companies by name or ticker. Shared by onboarding (picks) and the watchlist (adds).
struct StockSearchView: View {
    enum Mode {
        /// "+" toggles the onboarding selection; nothing reaches the backend yet.
        case onboarding(OnboardingSelection)
        /// "+" adds the stock to the watchlist (`add-stock` on the Moneta backend).
        case watchlist(MonetaStore)
    }

    let mode: Mode

    private enum Phase: Equatable {
        case loading, loaded, empty, failed
    }

    private struct SearchKey: Equatable {
        let query: String
        let attempt: Int
    }

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var popular: [Company] = []
    @State private var results: [Company] = []
    @State private var phase: Phase = .loading
    @State private var attempt = 0
    @State private var adding: Set<String> = []
    @FocusState private var searchFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandSearchField(prompt: "Search company or ticker", text: $query, focus: $searchFocused)
                Button("Cancel") { dismiss() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Brand.gold)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, Brand.margin)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Brand.spacing) {
                    if trimmed.isEmpty {
                        Text("Popular")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                            .padding(.leading, 4)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                    }
                    content
                }
                .padding(.horizontal, Brand.margin)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Brand.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Brand.background)
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                searchFocused = true
            }
        }
        // Changing the query cancels the previous task, so stale requests never land.
        .task(id: SearchKey(query: trimmed, attempt: attempt)) {
            await search(trimmed)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ForEach(0..<6, id: \.self) { _ in ShimmerRow() }
        case .failed:
            message(trimmed.isEmpty ? "Couldn’t load companies." : "Search failed. Check your connection.",
                    retry: true)
        case .empty:
            message("No companies found", retry: false)
        case .loaded:
            ForEach(trimmed.isEmpty ? popular : results) { company in
                SearchResultRow(
                    company: company,
                    isOn: isOn(company),
                    isBusy: adding.contains(company.ticker)
                ) {
                    tap(company)
                }
            }
        }
    }

    private func message(_ text: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: retry ? "wifi.exclamationmark" : "magnifyingglass")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Brand.muted)
            Text(text)
                .font(.callout)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
            if retry {
                Button("Try again") { attempt += 1 }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.gold)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Data

    private func search(_ q: String) async {
        if q.isEmpty {
            if !popular.isEmpty {
                phase = .loaded
                return
            }
            phase = .loading
            do {
                popular = try await featured()
                phase = popular.isEmpty ? .empty : .loaded
            } catch {
                if !Task.isCancelled { phase = .failed }
            }
            return
        }

        phase = .loading
        // Debounce: wait for typing to pause.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        do {
            let found = try await find(q)
            guard !Task.isCancelled else { return }
            results = found
            phase = found.isEmpty ? .empty : .loaded
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            phase = .failed
        }
    }

    private func featured() async throws -> [Company] {
        switch mode {
        case .onboarding: try await MonetaAPI.featuredCompanies()
        case .watchlist(let store): try await store.searchCompanies("")
        }
    }

    private func find(_ q: String) async throws -> [Company] {
        switch mode {
        case .onboarding: try await MonetaAPI.searchCompanies(q)
        case .watchlist(let store): try await store.searchCompanies(q)
        }
    }

    // MARK: Selection

    private func isOn(_ company: Company) -> Bool {
        switch mode {
        case .onboarding(let selection): selection.contains(company.ticker)
        case .watchlist(let store): store.isWatching(company.ticker)
        }
    }

    private func tap(_ company: Company) {
        switch mode {
        case .onboarding(let selection):
            selection.toggle(company)
        case .watchlist(let store):
            guard !store.isWatching(company.ticker), !adding.contains(company.ticker) else { return }
            adding.insert(company.ticker)
            Task {
                await store.addStock(company, settings: store.defaultSettings)
                adding.remove(company.ticker)
            }
        }
    }
}

private struct SearchResultRow: View {
    let company: Company
    let isOn: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CompanyLogo(company: company, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(company.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(company.ticker)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                    if company.isLiveWeb {
                        LiveWebBadge()
                    }
                }
            }
            Spacer(minLength: 8)
            Button(action: action) {
                AddToggleIcon(isOn: isOn, isBusy: isBusy)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .disabled(isBusy)
            .sensoryFeedback(.impact(weight: .light), trigger: isOn)
            .accessibilityLabel(isOn ? "Remove \(company.ticker)" : "Add \(company.ticker)")
            .accessibilityValue(isBusy ? "Adding" : isOn ? "Added" : "")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .brandCard()
        .accessibilityElement(children: .contain)
    }
}

/// "Live web": the hit came from Context.dev rather than Moneta's catalog.
private struct LiveWebBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Brand.gold).frame(width: 5, height: 5)
            Text("Live web")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Brand.gold)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Brand.gold.opacity(0.14), in: Capsule())
        .accessibilityLabel("Found live on the web")
    }
}
