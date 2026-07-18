/// The update-indication state shown in the status-menu header, owned by
/// `SlovoCore` so the whole silent download/ready lifecycle is unit-testable
/// without the Sparkle updater. `hidden` leaves the dropdown exactly as today.
public enum UpdateIndication: Equatable, Sendable {
    /// No update activity; the dropdown shows no update line.
    case hidden
    /// A newer version is downloading silently; the argument is that version.
    case downloading(version: String)
    /// A downloaded update is validated and ready to install; the argument is
    /// that version.
    case ready(version: String)

    /// The next indication state after an updater event, keeping the whole
    /// download → ready lifecycle a pure reduction the menu can test without
    /// Sparkle.
    ///
    /// Total over every (state, event) pair (house idiom: `DictationFsm`).
    /// `downloadStarted` and `downloaded` carry the EVENT's version, never
    /// the current state's, so the indication always names what the updater
    /// actually reported.
    public func applying(_ event: UpdaterEvent) -> UpdateIndication {
        switch event {
        case .found:
            // Found ≠ downloading: indication starts only when bytes move, so a
            // found-but-not-yet-downloading update leaves the state unchanged.
            return self
        case .downloadStarted(let version):
            return .downloading(version: version)
        case .downloaded(let version):
            // The event names what was downloaded, so a validated update is ready
            // even straight from `hidden`: a launch-resume of an already-fetched
            // update this run never saw start downloading.
            return .ready(version: version)
        case .aborted:
            // A downloaded update never regresses — a failed immediate install from
            // `ready` keeps the Restart row for another try; every other abort
            // (failed check/download) resets silently to `hidden`.
            if case .ready = self {
                return self
            }
            return .hidden
        }
    }
}

/// A background updater lifecycle signal the indication state reduces over,
/// mirroring the silent Sparkle pipeline (found → downloading → ready, or
/// aborted) without depending on any Sparkle type.
public enum UpdaterEvent: Sendable {
    /// A newer release was found; the silent download is about to start.
    case found
    /// The download of a newer version began; the argument is that version.
    case downloadStarted(version: String)
    /// A newer version finished downloading and validating; the argument is that
    /// version.
    case downloaded(version: String)
    /// The check, download, or validation failed or was aborted, so indication
    /// returns to no activity.
    case aborted
}
