import Foundation

/// Moneta's Supabase project. The publishable key is meant for clients; it only reaches what
/// row-level security allows. Context.dev and LLM keys stay on the backend.
enum BackendConfig {
    static let url = URL(string: "https://bxyqeamxplugchlfjhxz.supabase.co")!
    static let publishableKey = "sb_publishable_p17AsVNlaAutsJegSAQqGg_7SvxFS0X"
}
