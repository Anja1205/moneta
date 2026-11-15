import Foundation

/// Display formatting for prices, changes and times. Mock prices are USD.
enum Fmt {
    static func price(_ value: Double, currency: String = "USD") -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    /// Share counts: "10", "2.5", "0.125".
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
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

    /// "10:12" today, "Yesterday 22:18", "Fri 14:02" this week, "8 Nov 14:02" before.
    static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time(date))" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 6 {
            return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time(date)
        }
        return date.formatted(.dateTime.day().month(.abbreviated)) + " " + time(date)
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
