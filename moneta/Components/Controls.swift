import SafariServices
import SwiftUI

/// 44pt rounded-square glass icon button with a VoiceOver label.
struct IconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .contentShape(RoundedRectangle(cornerRadius: Metrics.iconButtonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.iconButtonRadius))
        .accessibilityLabel(label)
    }
}

/// Glass capsule segmented control (chart ranges, alert levels, filters).
struct GlassSegmented<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var accessibilityLabel: String

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.mSubheadline)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Palette.background : Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                Capsule().fill(Palette.amber)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(minHeight: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// [Web 10:12] - - - 28 min ahead - - - [+2.8% 10:40]
struct LeadTimeStrip: View {
    let signalTime: Date
    let reaction: MarketReaction?

    var body: some View {
        HStack(spacing: 8) {
            endpoint(title: "Web", value: Fmt.time(signalTime), color: Palette.amber)
            dashes
            Text(middleText)
                .font(.mCaption)
                .foregroundStyle(Palette.amber)
                .lineLimit(1)
                .fixedSize()
            dashes
            if let reaction, let at = reaction.at {
                endpoint(title: Fmt.percent(reaction.move), value: Fmt.time(at), color: Palette.change(reaction.move))
            } else {
                endpoint(title: "Market", value: "waiting", color: Palette.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var middleText: String {
        guard let minutes = reaction?.leadMinutes else { return "watching" }
        return "\(minutes) min ahead"
    }

    private var dashes: some View {
        Line()
            .stroke(Palette.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            .frame(height: 1.5)
            .frame(minWidth: 8)
    }

    private func endpoint(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.mCaption).monospacedDigit()
            Text(value).font(.mFootnote).monospacedDigit().foregroundStyle(Palette.secondary)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.tint(color), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }

    private var accessibilityText: String {
        guard let reaction, let at = reaction.at, let minutes = reaction.leadMinutes else {
            return "Seen on the web at \(Fmt.time(signalTime)). The market hasn't moved yet."
        }
        return "Seen on the web at \(Fmt.time(signalTime)), \(minutes) minutes before the price moved \(Fmt.percent(reaction.move)) at \(Fmt.time(at))."
    }

    private nonisolated struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// In-app browser for a signal's source.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#Preview {
    VStack(spacing: 20) {
        HStack { IconButton(systemImage: "bell", label: "Alerts") {} }
        GlassSegmented(options: ChartRange.allCases, selection: .constant(.day), title: \.rawValue, accessibilityLabel: "Range")
        LeadTimeStrip(signalTime: MockData.at(10, 12),
                      reaction: MarketReaction(signalTime: MockData.at(10, 12), move: 0.028, at: MockData.at(10, 40)))
    }
    .padding()
    .background(Palette.background)
}
