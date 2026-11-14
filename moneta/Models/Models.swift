import Foundation

/// A listed company Moneta can watch.
nonisolated struct Company: Identifiable, Hashable, Sendable {
    let ticker: String
    let name: String
    let exchange: String
    let sector: String
    /// Brand colour for logos and accents.
    let brandHex: UInt32
    /// SF Symbol used as the company mark in mock data.
    let symbol: String

    var id: String { ticker }
}

/// Where on the web a change was seen.
nonisolated enum SignalSource: String, CaseIterable, Identifiable, Hashable, Sendable {
    case news, x, careers, pricing, investor, changelog

    var id: String { rawValue }

    /// Tile title in "What Moneta watches".
    var watchTitle: String {
        switch self {
        case .news: "News & press"
        case .x: "Posts on X"
        case .careers: "Careers page"
        case .pricing: "Pricing pages"
        case .investor: "Investor pages"
        case .changelog: "Product changes"
        }
    }

    /// Short label on signal cards.
    var label: String {
        switch self {
        case .news: "News"
        case .x: "CEO on X"
        case .careers: "Careers page"
        case .pricing: "Pricing page"
        case .investor: "Investor page"
        case .changelog: "Changelog"
        }
    }

    var symbol: String {
        switch self {
        case .news: "newspaper"
        case .x: "bubble.left.and.text.bubble.right"
        case .careers: "person.2.badge.plus"
        case .pricing: "tag"
        case .investor: "building.columns"
        case .changelog: "shippingbox"
        }
    }
}

nonisolated enum Impact: Int, CaseIterable, Comparable, Hashable, Sendable {
    case low = 1, medium = 2, high = 3

    static func < (lhs: Impact, rhs: Impact) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .high: "High signal"
        case .medium: "Medium signal"
        case .low: "Low signal"
        }
    }

    var shortLabel: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

/// Which signals alert the user.
nonisolated enum AlertLevel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case highOnly, mediumUp, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highOnly: "High only"
        case .mediumUp: "Medium+"
        case .all: "All"
        }
    }

    var minimum: Impact {
        switch self {
        case .highOnly: .high
        case .mediumUp: .medium
        case .all: .low
        }
    }
}

/// One line of a page diff.
nonisolated struct DiffLine: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case unchanged, added, removed }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// A raw change the web monitor found, before the agent judges it.
nonisolated struct WebChange: Identifiable, Hashable, Sendable {
    let id: UUID
    let ticker: String
    let source: SignalSource
    let detectedAt: Date
    let title: String
    let url: URL
    let diff: [DiffLine]
    /// Context the monitor knows, e.g. "Page unchanged for 41 days".
    let facts: [String]
}

/// A change the agent decided matters, with its one-sentence "why".
nonisolated struct Signal: Identifiable, Hashable, Sendable {
    let id: UUID
    let ticker: String
    let source: SignalSource
    let impact: Impact
    let time: Date
    let title: String
    let why: String
    let url: URL
    let facts: [String]
    let diff: [DiffLine]
}

/// How the price moved after a signal, measured from the intraday series.
nonisolated struct MarketReaction: Hashable, Sendable {
    let signalTime: Date
    /// Fractional move from the price at the signal (0.028 = +2.8%).
    let move: Double
    /// When the price made most of that move; nil when it hasn't moved meaningfully (yet).
    let at: Date?
    /// True once an hour of prices has passed without a meaningful move, or the move happened.
    var settled: Bool = true

    /// Minutes the web was ahead of the market.
    var leadMinutes: Int? {
        at.map { max(Int($0.timeIntervalSince(signalTime) / 60), 1) }
    }
}

nonisolated struct PricePoint: Identifiable, Hashable, Sendable {
    let date: Date
    let price: Double
    var id: Date { date }
}

nonisolated struct Quote: Hashable, Sendable {
    let price: Double
    let previousClose: Double
    let updatedAt: Date

    var change: Double { price - previousClose }
    var changeFraction: Double { previousClose == 0 ? 0 : change / previousClose }
}

nonisolated struct PriceTick: Sendable {
    let ticker: String
    let point: PricePoint
}

nonisolated enum ChartRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case day = "1D", week = "1W", month = "1M", quarter = "3M", year = "1Y"
    var id: String { rawValue }
}

/// Per-stock watch settings.
nonisolated struct WatchSettings: Hashable, Sendable {
    var sources: Set<SignalSource>
    var alertLevel: AlertLevel

    static let standard = WatchSettings(sources: Set(SignalSource.allCases), alertLevel: .mediumUp)
}
