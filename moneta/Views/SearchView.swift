import SwiftUI

/// The Search tab: find a company, open it or add it.
struct SearchView: View {
    @Environment(MonetaStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var results: [Company] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if query.isEmpty {
                        Text("Popular")
                            .font(.mSubheadline)
                            .foregroundStyle(Palette.muted)
                            .padding(.leading, 4)
                    }
                    ForEach(results) { company in
                        row(company)
                    }
                    if results.isEmpty, !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .monetaScreen()
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Company or ticker")
            .monetaDestinations()
        }
        #if DEBUG
        .onAppear {
            if query.isEmpty, let preset = UserDefaults.standard.string(forKey: "MonetaSearch") { query = preset }
        }
        #endif
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            results = await store.search(query)
        }
    }

    @ViewBuilder
    private func row(_ company: Company) -> some View {
        let watching = store.isWatching(company.ticker)
        HStack(spacing: 12) {
            CompanyMark(company: company, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name)
                    .font(.mBodyStrong)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(company.detailLine)
                    .font(.mFootnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if watching {
                NavigationLink(value: Route.stock(company.ticker)) {
                    CapsuleTag("Watching", systemImage: "eye", color: Palette.amber)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Open \(company.name)")
            } else {
                Button {
                    router.addStock = AddStockTarget(company: company)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.amber)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.iconButtonRadius))
                .accessibilityLabel("Add \(company.name)")
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.border))
    }
}

#Preview {
    SearchView()
        .environment(MonetaStore.preview())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
