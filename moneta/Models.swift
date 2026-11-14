import Foundation

nonisolated struct Stock: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ticker: String
    let name: String
    let domain: String?
    let logoURL: String?
    let brandColor: String?
    let lastPolledAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, ticker, name, domain
        case logoURL = "logo_url"
        case brandColor = "brand_color"
        case lastPolledAt = "last_polled_at"
        case createdAt = "created_at"
    }

    static let columns = "id,ticker,name,domain,logo_url,brand_color,last_polled_at,created_at"
}

nonisolated enum SourceKind: String, Codable, Sendable {
    case news
    case irPage = "ir_page"
    case careers
    case pricing
    case demo
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SourceKind(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .news: "News"
        case .irPage: "Investor Relations"
        case .careers: "Careers"
        case .pricing: "Pricing"
        case .demo: "Demo"
        case .unknown: "Web"
        }
    }

    var symbol: String {
        switch self {
        case .news: "newspaper"
        case .irPage: "building.columns"
        case .careers: "person.2"
        case .pricing: "tag"
        case .demo: "sparkles"
        case .unknown: "globe"
        }
    }
}

nonisolated enum Direction: String, Codable, Sendable {
    case bullish, bearish, neutral

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Direction(rawValue: raw) ?? .neutral
    }

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .bullish: "arrow.up.right"
        case .bearish: "arrow.down.right"
        case .neutral: "arrow.right"
        }
    }
}

nonisolated struct Signal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let stockID: UUID
    let storyID: String
    let ticker: String
    let stockName: String
    let sourceKind: SourceKind
    let title: String
    let description: String?
    let url: String?
    let imageURL: String?
    let sourceName: String?
    let publishedAt: String?
    let detectedAt: String
    let impact: Int
    let direction: Direction
    let why: String
    let isNew: Bool

    enum CodingKeys: String, CodingKey {
        case id, ticker, title, description, url, impact, direction, why
        case stockID = "stock_id"
        case storyID = "story_id"
        case stockName = "stock_name"
        case sourceKind = "source_kind"
        case imageURL = "image_url"
        case sourceName = "source_name"
        case publishedAt = "published_at"
        case detectedAt = "detected_at"
        case isNew = "is_new"
    }

    var detectedDate: Date? { DateParser.parse(detectedAt) }
    var publishedDate: Date? { publishedAt.flatMap(DateParser.parse) }
    /// Best timestamp for display and sorting.
    var displayDate: Date { publishedDate ?? detectedDate ?? .distantPast }
    var clampedImpact: Int { min(max(impact, 1), 5) }
}

nonisolated struct AddStockRequest: Encodable, Sendable {
    let ticker: String
    let name: String
    let domain: String?
}

nonisolated struct AddStockResponse: Decodable, Sendable {
    let stock: Stock
    let added: Bool
}

/// Parses the ISO-8601 variants Postgres/PostgREST/Realtime emit:
/// `2026-11-14T14:02:01.826+00:00`, `2026-11-14 14:02:01.662326+00`, `...Z`, no fraction, no zone.
nonisolated enum DateParser {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 19 else { return nil }

        // Date/time separator.
        if s.count > 10 {
            let i = s.index(s.startIndex, offsetBy: 10)
            if s[i] == " " { s.replaceSubrange(i...i, with: "T") }
        }

        // Split into "yyyy-MM-ddTHH:mm:ss", optional fraction, optional zone.
        let base = String(s.prefix(19))
        var rest = Substring(s.dropFirst(19))

        var fraction = ""
        if rest.first == "." {
            rest = rest.dropFirst()
            let digits = rest.prefix { $0.isNumber }
            fraction = String(digits.prefix(3))
            while fraction.count < 3 { fraction += "0" }
            rest = rest.dropFirst(digits.count)
        }

        var zone = String(rest)
        if zone.isEmpty || zone == "Z" || zone == "z" {
            zone = "Z"
        } else if zone.first == "+" || zone.first == "-" {
            let sign = zone.removeFirst()
            let digits = zone.filter(\.isNumber)
            switch digits.count {
            case 2: zone = "\(sign)\(digits):00"
            case 4: zone = "\(sign)\(digits.prefix(2)):\(digits.suffix(2))"
            default: return nil
            }
        } else {
            return nil
        }

        if fraction.isEmpty {
            return plain.date(from: base + zone)
        }
        return withFraction.date(from: "\(base).\(fraction)\(zone)")
    }
}
