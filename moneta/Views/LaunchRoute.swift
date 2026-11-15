#if DEBUG
import Foundation

/// DEBUG only (`-MonetaPosition TICKER:shares:avgCost` / `TICKER:clear` sets a position, see RootView).
/// `-MonetaOpen splash|auth|authCreate|markets|stock|signal|signalLow|add|addORLA|signals|settings|search` opens a
/// screen on launch so layouts can be checked without tapping. No UI, compiled out of Release.
enum LaunchRoute {
    static var value: String? { UserDefaults.standard.string(forKey: "MonetaOpen") }
}
#endif
