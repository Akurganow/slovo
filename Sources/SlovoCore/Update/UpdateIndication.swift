/// The update-indication state shown in the always-visible status-menu update row,
/// owned by `SlovoCore` so the whole check → download → ready lifecycle is
/// unit-testable without the Sparkle updater. The row is never hidden: `idle` shows
/// an actionable "Check for Updates…" line, `checking` a transient "Checking…", and
/// the download/ready states the silent-update progress.
public enum UpdateIndication: Equatable, Sendable {
    /// No check in flight and no update staged: the row offers a manual check.
    case idle
    /// A check is in flight (scheduled OR user-initiated); the row reads "Checking…"
    /// and is not actionable until the check finishes.
    case checking
    /// A newer version is downloading silently; the argument is that version.
    case downloading(version: String)
    /// A downloaded update is validated and ready to install; the argument is
    /// that version.
    case ready(version: String)

    /// The next indication state after an updater event, keeping the whole
    /// check → download → ready lifecycle a pure reduction the menu can test
    /// without Sparkle.
    ///
    /// Total over every (state, event) pair (house idiom: `DictationFsm`).
    /// `downloadStarted` and `downloaded` carry the EVENT's version, never the
    /// current state's, so the indication always names what the updater reported.
    /// A downloaded/ready update NEVER regresses to a check or idle row — only a
    /// fresh `downloadStarted` moves it on.
    public func applying(_ event: UpdaterEvent) -> UpdateIndication {
        switch event {
        case .checkStarted:
            // Any check began (scheduled or manual): show Checking… — but never regress
            // a staged update (a background re-check must not hide the Restart row) nor
            // an in-flight download.
            switch self {
            case .ready, .downloading:
                return self
            case .idle, .checking:
                return .checking
            }
        case .found:
            // Found ≠ downloading: indication advances only when bytes move, so a
            // found-but-not-yet-downloading update keeps the current state (a check that
            // found something stays "Checking…" until the download actually starts).
            return self
        case .downloadStarted(let version):
            return .downloading(version: version)
        case .downloaded(let version):
            // The event names what was downloaded, so a validated update is ready even
            // straight from idle/checking: a launch-resume of an already-fetched update
            // this run never saw start downloading.
            return .ready(version: version)
        case .notFound:
            // A check found no update: back to the idle "Check for Updates…" row, but
            // never regress a staged update or an in-flight download.
            switch self {
            case .ready, .downloading:
                return self
            case .idle, .checking:
                return .idle
            }
        case .checkFinished:
            // Sparkle's GUARANTEED terminal (didFinishUpdateCycle): a Checking… state
            // can never stick — the end of ANY check cycle drops it to idle. This is the
            // stuck-state backstop even on the found-but-download-didn't-start path where
            // notFound never fires. Downloading/ready are mid/post-download states the
            // finished CHECK must not disturb; idle stays idle.
            if case .checking = self {
                return .idle
            }
            return self
        case .aborted:
            // A downloaded update never regresses — a failed immediate install from
            // `ready` keeps the Restart row for another try; every other abort (failed
            // check/download) returns to the idle check row.
            if case .ready = self {
                return self
            }
            return .idle
        }
    }
}

/// An updater lifecycle signal the indication state reduces over, mirroring the
/// silent Sparkle pipeline (check started → found → downloading → ready, or
/// not-found / finished / aborted) without depending on any Sparkle type.
public enum UpdaterEvent: Sendable {
    /// A check session began — scheduled or user-initiated. Fired for EVERY check
    /// (via Sparkle's `mayPerformUpdateCheck` gate), so a scheduled check also shows
    /// "Checking…", not only the manual button.
    case checkStarted
    /// A newer release was found; the silent download is about to start.
    case found
    /// The download of a newer version began; the argument is that version.
    case downloadStarted(version: String)
    /// A newer version finished downloading and validating; the argument is that
    /// version.
    case downloaded(version: String)
    /// A check finished finding no newer version (Sparkle's `updaterDidNotFindUpdate`).
    case notFound
    /// A check cycle finished — Sparkle's GUARANTEED terminal `didFinishUpdateCycle`,
    /// fired at the end of every check regardless of outcome. The backstop that keeps
    /// `checking` from sticking.
    case checkFinished
    /// The check, download, or validation failed or was aborted.
    case aborted
}
