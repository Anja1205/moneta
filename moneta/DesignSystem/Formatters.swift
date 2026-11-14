import Foundation

/// Display formatting for prices, changes and times. Mock prices are USD.
enum Fmt {
    static func price(_ value: Double, currency: String = "USD") -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    /// "+$3.42" / "−$1.10"
    static func signedPrice(_ value: Double, currency: String = "USD") -> String {
        let body = price(abs(value), currency: currency)
        if abs(value) < 0.005 { return body }
        return (value > 0 ? "+" : "−") + body
    }

    /// "+2.8%" / "−0.4%" / "0.0%" from a fraction (0.028).
    static func percent(_ fraction: Double, digits: Int = 1) -> String {
        let pct = fraction * 100
        let body = abs(pct).formatted(.number.precision(.fractionLength(digits)))
        if abs(pct) < pow(10, -Double(digits)) / 2 { return "0.\(String(repeating: "0", count: digits))%" }
        return (pct > 0 ? "+" : "−") + body + "%"
    }

    /// "10:12" — market times in 24-hour form.
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}
