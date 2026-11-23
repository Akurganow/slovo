import Foundation
import SlovoTestSupport
import Sparkle
import Testing
@testable import slovo
@testable import SlovoCore

/// How `UpdaterCoordinator` folds Sparkle's callbacks into the update indication.
/// Each test calls the delegate method directly on a coordinator whose updater was
/// never started. That updater reads the process's standard defaults when the host
/// bundle names no defaults domain (Sparkle 2.10.1, `Sparkle/SUHost.m:65-69`). It
/// writes nothing, and no assertion depends on what it reads.
@MainActor
@Suite("Updater coordinator mapping")
struct UpdaterCoordinatorMappingTests {
    /// Counts the coordinator's event reports.
    private final class Reports {
        var count = 0
    }

    private func makeCoordinator(
        indication: UpdateIndication
    ) -> (coordinator: UpdaterCoordinator, store: AppStore, reports: Reports) {
        let store = AppStore(state: AppState(config: Config(), isOpenRouterKeyPresent: false))
        store.update { $0.updateIndication = indication }
        let reports = Reports()
        let coordinator = UpdaterCoordinator(
            store: store,
            onUpdaterEvent: { reports.count += 1 },
            onInstallFailedAfterRestart: {}
        )
        return (coordinator, store, reports)
    }

    /// A scheduled check shows "Checking…": Sparkle's permission gate answers without
    /// throwing, the store shows the check and the event is reported once.
    /// Stated sensitivity: the gate drops or replaces its `.checkStarted` event, the
    /// call is left in the text but cannot run, or the method throws and refuses the
    /// check → RED.
    @Test
    func scheduledCheckShowsChecking() throws {
        let (coordinator, store, reports) = makeCoordinator(indication: .idle)

        try coordinator.updater(coordinator.updater, mayPerform: .updatesInBackground)

        #expect(store.state.updateIndication == .checking)
        #expect(reports.count == 1)
    }

    /// A check that found no update returns "Checking…" to idle, and leaves a download
    /// in flight alone.
    /// Stated sensitivity: the `.notFound` event is dropped or replaced by one that
    /// keeps "Checking…" → RED; replaced by `.aborted` → RED, since that would reset
    /// the download to idle.
    @Test
    func noUpdateFoundReturnsCheckingToIdle() {
        let (coordinator, store, reports) = makeCoordinator(indication: .checking)

        coordinator.updaterDidNotFindUpdate(coordinator.updater)

        #expect(store.state.updateIndication == .idle)
        #expect(reports.count == 1)

        let (busy, busyStore, busyReports) = makeCoordinator(indication: .downloading(version: "9.9.9"))

        busy.updaterDidNotFindUpdate(busy.updater)

        #expect(busyStore.state.updateIndication == .downloading(version: "9.9.9"))
        #expect(busyReports.count == 1)
    }

    /// The end of a check cycle returns "Checking…" to idle, with or without an error.
    /// Stated sensitivity: the `.checkFinished` event is dropped or replaced by one
    /// that keeps "Checking…", or the callback acts only when there is no error → RED.
    @Test
    func finishedCycleReturnsCheckingToIdleWithOrWithoutError() {
        let failure = NSError(domain: "test.updater", code: 1)
        for error in [nil, failure] {
            let (coordinator, store, reports) = makeCoordinator(indication: .checking)

            coordinator.updater(coordinator.updater, didFinishUpdateCycleFor: .updatesInBackground, error: error)

            #expect(store.state.updateIndication == .idle)
            #expect(reports.count == 1)
        }
    }
}
