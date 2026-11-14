import SwiftUI

struct AddStockView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var ticker = ""
    @State private var name = ""
    @State private var domain = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case ticker, name, domain }

    private var canSubmit: Bool {
        !ticker.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Track a stock")
                        .font(Theme.wordmark(size: 28))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Moneta watches its news, investor relations, careers and pricing pages, and scores every change.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 10) {
                    InputField(title: "Ticker", placeholder: "NVDA", text: $ticker)
                        .textInputAutocapitalization(.characters)
                        .focused($focused, equals: .ticker)
                        .submitLabel(.next)
                        .onSubmit { focused = .name }
                    InputField(title: "Company name", placeholder: "Nvidia", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .domain }
                    InputField(title: "Website (optional)", placeholder: "nvidia.com", text: $domain)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($focused, equals: .domain)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }
                .autocorrectionDisabled()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.bearish)
                }

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(Theme.background)
                        }
                        Text(isSubmitting ? "Adding…" : "Add to watchlist")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Theme.background)
                    .background(Theme.gold.opacity(canSubmit || isSubmitting ? 1 : 0.4),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { focused = .ticker }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            let error = await store.addStock(ticker: ticker, name: name, domain: domain)
            isSubmitting = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}

private struct InputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textTertiary))
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.stroke)
                )
        }
    }
}
