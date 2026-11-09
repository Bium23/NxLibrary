import Foundation

/// What the compatibility gate says (Settings → Engine, the Rebuild hints). A Metal compiler newer than the certified
/// one is information, an older one a warning; both still need the untested-toolchain override to build (AGENTS.md).
/// Any other failed check stays "Blocked".
public enum ToolchainGateCopy {
    /// A saved override can always be turned off once a certified engine arrives.
    /// While the newest engine is in use the override stays on: Back to tested turns it off.
    public static func canChangeOverride(certified: Bool?, overrideOn: Bool, locked: Bool, newest: Bool = false) -> Bool {
        !locked && !newest && (overrideOn || certified == false)
    }
    public enum Tone: Equatable, Sendable {
        case certified
        /// A newer Metal compiler: no alarm.
        case info
        /// An older Metal compiler: update recommended (orange).
        case warning
        case override
        case blocked
        /// The player chose nxnative main: it builds, untested by NX Library (orange, no alarm).
        case newest
    }

    public struct Summary: Equatable, Sendable {
        public let label: String
        public let tone: Tone
        /// One or two sentences under the status, nil when the label says it all.
        public let message: String?
        /// The short line where a build is refused (Spotlight, game page).
        public let buildHint: String
    }

    /// `newest`: the engine is the newest nxnative the player chose, so a passing check means "untested", never
    /// "Certified".
    public static func summary(report: CompatibilityReport, overrideOn: Bool, newest: Bool = false) -> Summary {
        if newest && report.ok {
            // The Newest engine row right below says the sentence; the panel only names the state.
            return Summary(label: L10n.text("Newest engine"), tone: .newest, message: nil, buildHint: "")
        }
        if report.ok { return Summary(label: L10n.text("Certified"), tone: .certified, message: nil, buildHint: "") }
        let blockers = report.checks.filter { $0.status == .block }
        if blockers.allSatisfy({ $0.id == "metal" }) {
            switch report.metal {
            case .newer(let installed, let required):
                let head = L10n.format("Your Metal compiler (%@) is newer than the one nxnative is tested with (%@).", [String(describing: (installed)), String(describing: (required))])
                return Summary(label: overrideOn ? L10n.text("Newer Metal · override on") : L10n.text("Newer Metal"), tone: .info,
                               message: head + (overrideOn ? L10n.text(" There should be no problems; builds are recorded as untested.")
                                                           : L10n.text(" There should be no problems: turn on Untested toolchain override to build.")),
                               buildHint: L10n.text("Newer Metal: turn on the override in Settings → Engine"))
            case .older(let installed, let required):
                let head = L10n.format("Your Metal compiler (%@) is older than the one nxnative needs (%@). ", [String(describing: (installed)), String(describing: (required))])
                    + L10n.format("Updating to Metal %@ is strongly recommended.", [String(describing: (required))])
                return Summary(label: overrideOn ? L10n.text("Older Metal · override on") : L10n.text("Update recommended"), tone: .warning,
                               message: head + (overrideOn ? L10n.text(" Builds are recorded as untested.")
                                                           : L10n.text(" Untested toolchain override builds anyway, at your own risk.")),
                               buildHint: L10n.text("Older Metal: update it, or use the override in Settings → Engine"))
            case .same, .unknown:
                break
            }
        }
        return overrideOn
            ? Summary(label: L10n.text("Override enabled"), tone: .override, message: nil, buildHint: "")
            : Summary(label: L10n.text("Blocked"), tone: .blocked, message: nil, buildHint: L10n.text("Build blocked — Settings → Engine"))
    }
}
