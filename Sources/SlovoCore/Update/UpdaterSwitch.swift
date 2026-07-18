/// The single updater control the automatic-update preference drives, named to
/// match `SPUUpdater.automaticallyChecksForUpdates` so the app target can conform
/// Sparkle's updater to it retroactively. Declared in `SlovoCore` with no Sparkle
/// import, keeping the activation policy pure and unit-testable.
public protocol UpdaterSwitch: AnyObject {
    /// Whether the updater runs its scheduled background checks. Off stops the
    /// whole pipeline — no feed fetch, no download — so this is the one property
    /// the preference toggles.
    var automaticallyChecksForUpdates: Bool { get set }
}

/// Applies the user's automatic-update preference to an `UpdaterSwitch`, so the
/// "off ⇒ zero update-network activity" rule lives in one pure, testable place
/// rather than in the app's Sparkle wiring.
public enum UpdaterActivation {
    /// Configures `updater` from the stored preference in a single assignment, so
    /// "off ⇒ zero update-network activity" holds with no transient on-then-off
    /// window that would leak a brief scheduled check.
    public static func apply(automaticUpdatesEnabled: Bool, to updater: UpdaterSwitch) {
        updater.automaticallyChecksForUpdates = automaticUpdatesEnabled
    }
}
