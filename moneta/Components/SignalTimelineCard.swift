import SwiftUI

/// Timeline card: numbered pin, "time · source", the price move after it, title and the why.
struct SignalTimelineCard: View {
    let signal: Signal
    let number: Int
    let reaction: MarketReaction?
    var company: Company? = nil
    var isFresh = false
    var isMuted = false

    var body: some View {
        Card(border: isFresh ? Palette.amber : Palette.border) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SignalPin(number: number, impact: signal.impact)
                    VStack(alignment: .leading, spacing: 1) {
                        if let company {
                            Text(company.ticker)
                                .font(.mSubheadline)
                                .foregroundStyle(Palette.text)
                        }
                        Text("\(Fmt.time(signal.time)) · \(signal.source.label)")
                            .font(.mFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if isMuted {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .accessibilityLabel("Muted")
                    }
                    moveView
                }
                Text(signal.title)
                    .font(.mHeadline)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(signal.why)
                    .font(.mCallout)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .shadow(color: isFresh ? Palette.amber.opacity(0.25) : .clear, radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the signal")
    }

    @ViewBuilder
    private var moveView: some View {
        if let reaction, reaction.at != nil {
            ChangeCapsule(fraction: reaction.move)
        } else if let reaction, reaction.settled {
            // No meaningful move within the hour.
            ChangeCapsule(fraction: 0)
        } else {
            CapsuleTag("Watching", systemImage: "clock", color: Palette.muted)
        }
    }
}

#Preview {
    let seeded = MockData.seeded[0]
    let signal = Signal(id: seeded.change.id, ticker: "VNTR", source: .investor, impact: .high,
                        time: seeded.change.detectedAt, title: seeded.change.title, why: seeded.assessment.why,
                        url: seeded.change.url, facts: seeded.change.facts, diff: seeded.change.diff)
    SignalTimelineCard(signal: signal, number: 1,
                       reaction: MarketReaction(signalTime: signal.time, move: 0.028, at: signal.time.addingTimeInterval(1680)))
        .padding()
        .background(Palette.background)
}
