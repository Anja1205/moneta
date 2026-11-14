import Foundation

/// Fictional companies and the day's seeded web changes. Mock only.
enum MockData {
    static let companies: [Company] = [
        Company(ticker: "VNTR", name: "Vantor Robotics", exchange: "NASDAQ", sector: "Industrial robotics", brandHex: 0x7C8CFF, symbol: "gearshape.2.fill"),
        Company(ticker: "KSTL", name: "Kestrel Air", exchange: "NYSE", sector: "Airlines", brandHex: 0x4FC3F7, symbol: "airplane"),
        Company(ticker: "HLDN", name: "Halden Semiconductor", exchange: "NASDAQ", sector: "Semiconductors", brandHex: 0xB38CFF, symbol: "cpu.fill"),
        Company(ticker: "ORLA", name: "Orla Foods", exchange: "NYSE", sector: "Packaged foods", brandHex: 0x7FD67A, symbol: "leaf.fill"),
        Company(ticker: "BRMR", name: "Brightmere Retail", exchange: "NYSE", sector: "Retail", brandHex: 0xFF9F7A, symbol: "bag.fill"),
    ]

    /// Watched when the app first opens.
    static let initialWatchlist = ["VNTR", "KSTL", "HLDN", "BRMR"]

    struct PriceSeed {
        let previousClose: Double
        let open: Double
        let volatility: Double
    }

    static let prices: [String: PriceSeed] = [
        "VNTR": PriceSeed(previousClose: 118.40, open: 118.62, volatility: 0.00045),
        "KSTL": PriceSeed(previousClose: 42.15, open: 42.08, volatility: 0.0005),
        "HLDN": PriceSeed(previousClose: 212.80, open: 213.40, volatility: 0.0004),
        "ORLA": PriceSeed(previousClose: 27.35, open: 27.31, volatility: 0.00035),
        "BRMR": PriceSeed(previousClose: 63.90, open: 64.05, volatility: 0.0004),
    ]

    /// A seeded change with the agent's verdict and the market's later reaction.
    struct SeededChange {
        let change: WebChange
        let assessment: SignalAssessment
        /// Move the mock market makes after the change (0 = none), and how many minutes later.
        let move: Double
        let lead: Int
    }

    /// Today's session in the user's calendar.
    static func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static let seeded: [SeededChange] = [
        seed("VNTR", .investor, 10, 12, "Second automotive customer added",
             url: "https://example.com/vantor/investors/customers",
             diff: [(.unchanged, "Automotive customers"),
                    (.unchanged, "Lumen Motors — welding cells since 2024"),
                    (.added, "Brenner Automobil — body-shop pilot line, 2026")],
             facts: ["Not in the news yet", "Page unchanged for 41 days"],
             impact: .high, why: "Not reported yet, and it hints at a much bigger backlog.", move: 0.028, lead: 28),
        seed("VNTR", .careers, 13, 5, "34 robotics roles posted in Stuttgart",
             url: "https://example.com/vantor/careers?location=stuttgart",
             diff: [(.unchanged, "Open roles · Stuttgart"),
                    (.removed, "2 open positions"),
                    (.added, "36 open positions (34 new: robotics, controls, field service)")],
             facts: ["Up from 2 roles last week", "No press release"],
             impact: .medium, why: "A hiring push in Germany fits a new carmaker deal.", move: 0.006, lead: 21),
        seed("VNTR", .x, 14, 48, "Factory-floor video from the CEO",
             url: "https://example.com/vantor/ceo-post",
             diff: [(.added, "“New cell line running at full speed in Ohio 🚀”")],
             facts: ["Posted by the CEO", "No figures mentioned"],
             impact: .low, why: "Mostly promotional, with no new figures.", move: 0, lead: 0),
        seed("HLDN", .investor, 9, 48, "Earnings call moved up by a week",
             url: "https://example.com/halden/investors/events",
             diff: [(.removed, "Q3 results call: 21 November, 16:30"),
                    (.added, "Q3 results call: 14 November, 16:30")],
             facts: ["Not in the news yet", "Date unchanged since August"],
             impact: .high, why: "Companies rarely bring results forward unless they're keen to share them.", move: 0.019, lead: 44),
        seed("HLDN", .changelog, 12, 30, "SDK notes mention 3nm test chips",
             url: "https://example.com/halden/sdk/changelog",
             diff: [(.unchanged, "SDK 8.4"),
                    (.added, "Added: simulation profiles for 3nm test silicon")],
             facts: ["Developer docs only"],
             impact: .low, why: "Interesting for the roadmap, but nothing changes this quarter.", move: 0, lead: 0),
        seed("KSTL", .pricing, 11, 20, "Fares up 9% on 12 European routes",
             url: "https://example.com/kestrel/fares",
             diff: [(.unchanged, "Lisbon – Berlin, economy"),
                    (.removed, "from $129"),
                    (.added, "from $141")],
             facts: ["12 of 40 routes changed", "Competitors unchanged"],
             impact: .medium, why: "A broad fare rise points to strong summer demand.", move: 0.011, lead: 35),
        seed("BRMR", .news, 13, 40, "Regional chain to close 14 stores",
             url: "https://example.com/news/brightmere-closures",
             diff: [(.added, "Brightmere will close 14 stores in the Midwest by March.")],
             facts: ["Local paper, not national press yet"],
             impact: .medium, why: "Store closures cut revenue in its weakest region.", move: -0.014, lead: 22),
        seed("ORLA", .changelog, 11, 5, "New ready-meal line on product pages",
             url: "https://example.com/orla/products",
             diff: [(.unchanged, "Products"),
                    (.added, "Orla Kitchen — 8 ready meals, in stores from 1 December")],
             facts: ["Not announced yet", "Product pages unchanged for 3 months"],
             impact: .medium, why: "A new category could lift sales growth next year.", move: 0.008, lead: 31),
    ]

    private static func seed(
        _ ticker: String, _ source: SignalSource, _ hour: Int, _ minute: Int, _ title: String,
        url: String, diff: [(DiffLine.Kind, String)], facts: [String],
        impact: Impact, why: String, move: Double, lead: Int
    ) -> SeededChange {
        SeededChange(
            change: WebChange(
                id: UUID(), ticker: ticker, source: source, detectedAt: at(hour, minute), title: title,
                url: URL(string: url)!, diff: diff.map { DiffLine(kind: $0.0, text: $0.1) }, facts: facts
            ),
            assessment: SignalAssessment(impact: impact, why: why),
            move: move, lead: lead
        )
    }

    /// Templates for "live" changes that arrive while the app runs.
    struct Template {
        let source: SignalSource
        let impact: Impact
        let title: String
        let why: String
        let move: ClosedRange<Double>
        let diff: [(DiffLine.Kind, String)]
        let facts: [String]
    }

    static let liveTemplates: [Template] = [
        Template(source: .careers, impact: .medium, title: "28 engineering roles opened in Austin",
                 why: "A hiring burst like this usually comes before a capacity push.", move: 0.004...0.012,
                 diff: [(.removed, "Austin · 3 open roles"), (.added, "Austin · 31 open roles")],
                 facts: ["Biggest jump this year", "No press release"]),
        Template(source: .pricing, impact: .high, title: "List prices raised 12% across the core range",
                 why: "A price rise this size lifts margins if demand holds.", move: 0.015...0.03,
                 diff: [(.removed, "Core plan · $49 / month"), (.added, "Core plan · $55 / month")],
                 facts: ["Not in the news yet", "Prices unchanged for 14 months"]),
        Template(source: .news, impact: .medium, title: "Trade press reports supplier delays",
                 why: "Supply problems can push deliveries into next quarter.", move: -0.015 ... -0.005,
                 diff: [(.added, "“Two key suppliers are running six weeks late,” the report says.")],
                 facts: ["Trade press only"]),
        Template(source: .investor, impact: .high, title: "Investor page adds an unscheduled update call",
                 why: "Unscheduled calls often come with a change to guidance.", move: -0.025...0.025,
                 diff: [(.added, "Business update call — tomorrow, 08:00")],
                 facts: ["Not in the news yet", "No call was planned"]),
        Template(source: .x, impact: .low, title: "CEO shares a photo from the new office",
                 why: "Mostly promotional, with no new figures.", move: 0...0,
                 diff: [(.added, "“Day one in the new HQ.”")], facts: ["No figures mentioned"]),
        Template(source: .changelog, impact: .low, title: "Changelog lists a minor app update",
                 why: "Routine release, unlikely to move the stock.", move: 0...0,
                 diff: [(.unchanged, "Version 5.12"), (.added, "Bug fixes and performance improvements")],
                 facts: ["Routine release"]),
    ]
}

/// Verdicts for mock changes, shared between the mock monitor and the mock agent.
@MainActor
final class MockRegistry {
    static let shared = MockRegistry()
    var assessments: [UUID: SignalAssessment] = [:]

    private init() {
        for seed in MockData.seeded {
            assessments[seed.change.id] = seed.assessment
        }
    }
}

/// Small deterministic random generator so mock charts look the same on every launch.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// Stable seed per ticker.
    var stableSeed: UInt64 {
        unicodeScalars.reduce(1469598103934665603) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }
}
