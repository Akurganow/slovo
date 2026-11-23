import Testing

import SlovoCore

// The pure updater-event → indication-state reducer (`UpdateIndication.applying(_:)`),
// pinned as a transition table of lossless no-ops (house idiom: DictationFsm). The
// row is always visible now: `idle` ("Check for Updates…") and `checking`
// ("Checking…") are live states, and a staged download/ready update never regresses.
@Suite("Update indication reducer")
struct UpdateIndicationTests {
    // MARK: check started (scheduled OR manual)

    /// A check beginning turns the idle row into "Checking…".
    /// Stated sensitivity: map `checkStarted` to identity (stays `.idle`) → the row
    /// never shows a check is running → RED.
    @Test
    func checkStartedFromIdleShowsChecking() {
        #expect(UpdateIndication.idle.applying(.checkStarted) == .checking)
    }

    /// A background re-check starting while an update is already staged must NOT hide
    /// the Restart row.
    /// Stated sensitivity: map `checkStarted` → `.checking` uniformly → the ready row
    /// (and its Restart action) vanishes on the next hourly re-check → RED.
    @Test
    func checkStartedFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.checkStarted) == .ready(version: "0.14.0"))
    }

    /// A re-check firing mid-download does not regress the downloading line.
    /// Stated sensitivity: map `checkStarted` → `.checking` uniformly → the download
    /// row vanishes → RED.
    @Test
    func checkStartedFromDownloadingKeepsDownloading() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.checkStarted) == .downloading(version: "0.14.0"))
    }

    // MARK: found (during a check)

    /// An update merely FOUND stays "Checking…" — indication advances only when the
    /// download actually starts.
    /// Stated sensitivity: map `found` to `.downloading` → ≠ `.checking` → RED.
    @Test
    func foundFromCheckingStaysChecking() {
        #expect(UpdateIndication.checking.applying(.found) == .checking)
    }

    /// A re-check finding an update while one is already downloaded changes nothing:
    /// ready survives `found` (the "events after ready don't regress it" rule).
    /// Stated sensitivity: map `found` → non-ready uniformly → the Restart row vanishes
    /// on the next hourly re-check → RED.
    @Test
    func foundFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.found) == .ready(version: "0.14.0"))
    }

    // MARK: download lifecycle

    /// The download starting turns indication on: checking → downloading, carrying the
    /// event's version.
    /// Stated sensitivity: keep the identity mapping (stays `.checking`) or drop the
    /// version payload → ≠ `.downloading(version: "0.14.0")` → RED.
    @Test
    func downloadStartedFromCheckingShowsDownloading() {
        #expect(UpdateIndication.checking.applying(.downloadStarted(version: "0.14.0")) == .downloading(version: "0.14.0"))
    }

    /// A superseding download starting mid-download retargets the line to the EVENT's
    /// version — the newest reported download wins.
    /// Stated sensitivity: keep the stale state version →
    /// `.downloading(version: "0.14.0")` ≠ `.downloading(version: "0.15.0")` → RED.
    @Test
    func downloadStartedFromDownloadingRetargetsToEventVersion() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.downloadStarted(version: "0.15.0")) == .downloading(version: "0.15.0"))
    }

    /// A validated download flips downloading → ready, carrying the EVENT's version.
    /// Stated sensitivity: identity mapping stays `.downloading` → RED; copy the
    /// state's version → `.ready(version: "0.14.0")` ≠ `.ready(version: "0.15.0")` → RED.
    @Test
    func downloadedFromDownloadingBecomesReady() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.downloaded(version: "0.15.0")) == .ready(version: "0.15.0"))
    }

    /// A newer download completing while an older one is already ready replaces the
    /// ready version with the EVENT's.
    /// Stated sensitivity: freeze `ready` against `downloaded` →
    /// `.ready(version: "0.14.0")` ≠ `.ready(version: "0.15.0")` → RED.
    @Test
    func downloadedFromReadyCarriesEventVersion() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.downloaded(version: "0.15.0")) == .ready(version: "0.15.0"))
    }

    /// Launch-resume: an ALREADY-downloaded update reported with no `downloadStarted`
    /// seen this run — idle jumps straight to ready.
    /// Stated sensitivity: gate the ready mapping on a prior `.downloading` (or keep the
    /// identity mapping) → stays `.idle` → RED.
    @Test
    func downloadedFromIdleResumesAsReady() {
        #expect(UpdateIndication.idle.applying(.downloaded(version: "0.14.0")) == .ready(version: "0.14.0"))
    }

    /// A fresh cycle supersedes a ready update: a NEW download starting from ready shows
    /// downloading with the NEW version — the one event that moves the state off ready.
    /// Stated sensitivity: freeze `ready` against all events or keep the old version →
    /// ≠ `.downloading(version: "0.15.0")` → RED.
    @Test
    func downloadStartedFromReadyBeginsFreshCycle() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.downloadStarted(version: "0.15.0")) == .downloading(version: "0.15.0"))
    }

    // MARK: terminal transitions — the stuck-`checking` guard

    /// A check finding no update returns Checking… → the idle "Check for Updates…" row.
    /// Stated sensitivity: drop the `notFound → .idle` arm (identity keeps `.checking`)
    /// → the row sticks on "Checking…" after an empty check → RED.
    @Test
    func notFoundFromCheckingReturnsToIdle() {
        #expect(UpdateIndication.checking.applying(.notFound) == .idle)
    }

    /// `notFound` on a hourly re-check while an update is already staged must NOT hide
    /// the Restart row.
    /// Stated sensitivity: map `notFound` → `.idle` uniformly → the ready row vanishes
    /// on the next empty re-check → RED.
    @Test
    func notFoundFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.notFound) == .ready(version: "0.14.0"))
    }

    /// The GUARANTEED terminal: Sparkle's `didFinishUpdateCycle` fires at the end of
    /// EVERY check, so a Checking… state can never stick — even on the
    /// found-but-download-didn't-start path where `notFound` never fires.
    /// Stated sensitivity: drop the `checkFinished → .idle` arm (identity keeps
    /// `.checking`) → Checking… sticks forever after such a check → RED (the stuck-state
    /// mutant).
    @Test
    func checkFinishedFromCheckingReturnsToIdle() {
        #expect(UpdateIndication.checking.applying(.checkFinished) == .idle)
    }

    /// The finished CHECK must not disturb a mid-download or staged update.
    /// Stated sensitivity: map `checkFinished` → `.idle` uniformly → the download/ready
    /// row vanishes when the check cycle reports finished → RED.
    @Test
    func checkFinishedDoesNotRegressDownloadingOrReady() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.checkFinished) == .downloading(version: "0.14.0"))
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.checkFinished) == .ready(version: "0.14.0"))
    }

    /// A failed/aborted check returns Checking… → idle silently.
    /// Stated sensitivity: drop the `aborted → .idle` arm (identity keeps `.checking`)
    /// → a failed check sticks on "Checking…" → RED.
    @Test
    func abortedFromCheckingReturnsToIdle() {
        #expect(UpdateIndication.checking.applying(.aborted) == .idle)
    }

    /// A failed download returns to the idle check row silently.
    /// Stated sensitivity: drop the `aborted → .idle` reset (identity keeps
    /// `.downloading`) → the silent-failure reset is lost → RED.
    @Test
    func abortedFromDownloadingReturnsToIdle() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.aborted) == .idle)
    }

    /// A failed immediate install must NEVER regress a downloaded update: ready survives
    /// `aborted`, keeping the Restart row for another try.
    /// Stated sensitivity: map `aborted` uniformly to `.idle` → the ready row vanishes → RED.
    @Test
    func abortedFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.aborted) == .ready(version: "0.14.0"))
    }

    /// Totality: terminal events with nothing in flight are lossless no-ops — idle
    /// stays idle, never a crash, never a spurious line.
    /// Stated sensitivity: make an idle terminal cell surface anything → ≠ `.idle` → RED.
    @Test
    func terminalEventsFromIdleStayIdle() {
        #expect(UpdateIndication.idle.applying(.aborted) == .idle)
        #expect(UpdateIndication.idle.applying(.notFound) == .idle)
        #expect(UpdateIndication.idle.applying(.checkFinished) == .idle)
        #expect(UpdateIndication.idle.applying(.found) == .idle)
    }

    // MARK: failed check or download

    /// A failed check or download shows the failure from every state but a staged update.
    /// Stated sensitivity: map `failed` like `aborted` (idle) → the failure is never
    /// shown → RED.
    @Test
    func failedFromIdleCheckingAndDownloadingShowsCheckFailed() {
        #expect(UpdateIndication.idle.applying(.failed) == .checkFailed)
        #expect(UpdateIndication.checking.applying(.failed) == .checkFailed)
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.failed) == .checkFailed)
    }

    /// A failed immediate install from `ready` keeps the Restart row for another try.
    /// Stated sensitivity: `failed` from `ready` gives `.checkFailed` → the Restart row
    /// vanishes → RED.
    @Test
    func failedFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.failed) == .ready(version: "0.14.0"))
    }

    /// The failed row stays until the next check starts, then the cycle goes on as usual.
    /// Stated sensitivity: `checkStarted` keeps `.checkFailed` → the row never shows the
    /// new check → RED.
    @Test
    func checkFailedYieldsToTheNextCycle() {
        #expect(UpdateIndication.checkFailed.applying(.checkStarted) == .checking)
        #expect(UpdateIndication.checkFailed.applying(.downloadStarted(version: "0.14.0")) == .downloading(version: "0.14.0"))
        #expect(UpdateIndication.checkFailed.applying(.downloaded(version: "0.14.0")) == .ready(version: "0.14.0"))
    }

    /// The terminal callbacks of the failed cycle must not erase the failure.
    /// Stated sensitivity: `checkFinished` (or `notFound`, `found`, `aborted`) clears
    /// `.checkFailed` to idle → the failure flashes by unseen → RED.
    @Test
    func terminalEventsKeepCheckFailed() {
        #expect(UpdateIndication.checkFailed.applying(.found) == .checkFailed)
        #expect(UpdateIndication.checkFailed.applying(.notFound) == .checkFailed)
        #expect(UpdateIndication.checkFailed.applying(.checkFinished) == .checkFailed)
        #expect(UpdateIndication.checkFailed.applying(.aborted) == .checkFailed)
    }
}
