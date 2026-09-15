import Foundation

/// TestFlight, device testing, simulator and release builds share one cloud studio.
/// Old saved LAN addresses and review build settings never override this origin.
enum StudioConnection {
    static let cloudURL = "https://3d-craft.web.app"

    static func initial(saved: String?, configured: String?, simulator: Bool) -> String {
        cloudURL
    }
}
