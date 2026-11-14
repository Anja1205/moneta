import Foundation

enum Config {
    static let supabaseURL = URL(string: "https://bxyqeamxplugchlfjhxz.supabase.co")!
    /// Publishable key: safe to ship in the app.
    static let supabaseKey = "sb_publishable_p17AsVNlaAutsJegSAQqGg_7SvxFS0X"
    /// Signals at or above this impact (1-5) count as alerts.
    static let alertImpact = 4
}
