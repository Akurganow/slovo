import Testing

import SlovoCore

// The pure updater-event → indication-state reducer
// (`UpdateIndication.applying(_:)`), pinned as a transition table of lossless
// no-ops (house idiom: DictationFsm):
//
//   state \ event  | found          | downloadStarted(v) | downloaded(v)     | aborted
//   hidden         | hidden         | downloading(v)     | ready(v) [resume] | hidden
//   downloading(u) | downloading(u) | downloading(v)     | ready(v)          | hidden
//   ready(u)       | ready(u)       | downloading(v)     | ready(v)          | ready(u)
@Suite("Update indication reducer")
struct UpdateIndicationTests {
    /// An update merely FOUND shows nothing — indication starts only when the
    /// download starts, so a found-but-not-yet-downloading update keeps the
    /// dropdown exactly today's.
    /// Stated sensitivity: map `found` to `.downloading` (indication on
    /// found) → ≠ `.hidden` → RED.
    @Test
    func foundFromHiddenStaysSilent() {
        #expect(UpdateIndication.hidden.applying(.found) == .hidden)
    }

    /// A re-check firing mid-download is a no-op: the downloading line keeps
    /// its version until the updater reports actual progress.
    /// Stated sensitivity: map `found` → `.hidden` uniformly → the downloading
    /// row vanishes on the next re-check → RED.
    @Test
    func foundFromDownloadingKeepsDownloading() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.found) == .downloading(version: "0.14.0"))
    }

    /// A re-check finding an update while one is already downloaded changes
    /// nothing: ready survives `found` — the spec's "events after ready don't
    /// regress it".
    /// Stated sensitivity: map `found` → `.hidden` uniformly → the ready row
    /// (and its Restart action) vanishes on the next hourly re-check → RED.
    @Test
    func foundFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.found) == .ready(version: "0.14.0"))
    }

    /// The download starting is what turns indication on: hidden → downloading,
    /// carrying the event's version.
    /// Stated sensitivity: keep the identity mapping (stays `.hidden`) or drop
    /// the version payload → ≠ `.downloading(version: "0.14.0")` → RED.
    @Test
    func downloadStartedFromHiddenShowsDownloading() {
        let next = UpdateIndication.hidden.applying(.downloadStarted(version: "0.14.0"))
        #expect(next == .downloading(version: "0.14.0"))
    }

    /// A superseding download starting mid-download retargets the line to the
    /// EVENT's version — the newest reported download wins (table cell:
    /// downloading(u) + downloadStarted(v) → downloading(v)).
    /// Stated sensitivity: keep the stale state version →
    /// `.downloading(version: "0.14.0")` ≠ `.downloading(version: "0.15.0")` → RED.
    @Test
    func downloadStartedFromDownloadingRetargetsToEventVersion() {
        let next = UpdateIndication.downloading(version: "0.14.0").applying(.downloadStarted(version: "0.15.0"))
        #expect(next == .downloading(version: "0.15.0"))
    }

    /// A validated download flips the header slot from downloading to ready,
    /// carrying the EVENT's version — the event, not the stale state payload,
    /// names what was actually downloaded (table cell: downloading(u) +
    /// downloaded(v) → ready(v)).
    /// Stated sensitivity: identity mapping stays `.downloading` → RED; copy
    /// the state's version instead of the event's → `.ready(version: "0.14.0")`
    /// ≠ `.ready(version: "0.15.0")` → RED.
    @Test
    func downloadedFromDownloadingBecomesReady() {
        let next = UpdateIndication.downloading(version: "0.14.0").applying(.downloaded(version: "0.15.0"))
        #expect(next == .ready(version: "0.15.0"))
    }

    /// A newer download completing while an older one is already ready
    /// replaces the ready version with the EVENT's — the indication always
    /// names what the updater validated last (table cell: ready(u) +
    /// downloaded(v) → ready(v)).
    /// Stated sensitivity: freeze `ready` against `downloaded` (keep ready(u))
    /// → `.ready(version: "0.14.0")` ≠ `.ready(version: "0.15.0")` → RED.
    @Test
    func downloadedFromReadyCarriesEventVersion() {
        let next = UpdateIndication.ready(version: "0.14.0").applying(.downloaded(version: "0.15.0"))
        #expect(next == .ready(version: "0.15.0"))
    }

    /// Launch-resume: the updater can report an ALREADY-downloaded update with
    /// no `downloadStarted` seen this run — hidden jumps straight to ready.
    /// Stated sensitivity: gate the ready mapping on a prior `.downloading`
    /// state (or keep the identity mapping) → stays `.hidden` → RED.
    @Test
    func downloadedFromHiddenResumesAsReady() {
        let next = UpdateIndication.hidden.applying(.downloaded(version: "0.14.0"))
        #expect(next == .ready(version: "0.14.0"))
    }

    /// A failed or aborted download resets indication silently: downloading →
    /// hidden — the spec's "failed check/download shows nothing".
    /// Stated sensitivity: drop the abort→hidden transition (the identity
    /// mapping keeps `.downloading`) → the silent-failure reset is lost → RED.
    @Test
    func abortedFromDownloadingHidesSilently() {
        #expect(UpdateIndication.downloading(version: "0.14.0").applying(.aborted) == .hidden)
    }

    /// A failed immediate install must NEVER regress a downloaded update:
    /// ready survives `aborted`, keeping the Restart row available for another
    /// try (spec: "retry stays available").
    /// Stated sensitivity: map `aborted` uniformly to `.hidden` (the tempting
    /// abort-resets-everything mutation) → the ready row vanishes → RED.
    @Test
    func abortedFromReadyKeepsReady() {
        #expect(UpdateIndication.ready(version: "0.14.0").applying(.aborted) == .ready(version: "0.14.0"))
    }

    /// A fresh cycle supersedes a ready update: a NEW download starting from
    /// ready shows downloading with the NEW version — the one event that may
    /// move the state off `ready`.
    /// Stated sensitivity: freeze `ready` against all events (overshooting the
    /// never-regress rule) or keep the old version → ≠
    /// `.downloading(version: "0.15.0")` → RED.
    @Test
    func downloadStartedFromReadyBeginsFreshCycle() {
        let next = UpdateIndication.ready(version: "0.14.0").applying(.downloadStarted(version: "0.15.0"))
        #expect(next == .downloading(version: "0.15.0"))
    }

    /// Totality: `aborted` with nothing in flight is a lossless no-op — hidden
    /// stays hidden, never a crash, never a spurious line.
    /// Stated sensitivity: make the hidden+aborted cell surface anything →
    /// ≠ `.hidden` → RED.
    @Test
    func abortedFromHiddenStaysHidden() {
        #expect(UpdateIndication.hidden.applying(.aborted) == .hidden)
    }
}
