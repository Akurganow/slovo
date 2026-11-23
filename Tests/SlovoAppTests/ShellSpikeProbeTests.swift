import AppKit
import Settings
import SlovoTestSupport
import Sparkle
import Testing
import os

@testable import slovo
@testable import SlovoCore

private struct NoFnKeyAssignment: FnKeyAssignmentReading {
    let isFnKeySystemAssigned = false
}

@MainActor
@Suite("App shell spike probe")
struct ShellSpikeProbeTests {
    private func makeStore(defaults: UserDefaults) -> AppStore {
        AppStore(state: AppState(
            config: ConfigStore.load(from: defaults),
            isOpenRouterKeyPresent: false,
            isFnKeySystemAssigned: false
        ))
    }

    // Stated sensitivity: renaming "Quit Slovo" or dropping a top-level item in AppMainMenu.make() → RED
    @Test
    func mainMenuHoldsAppAndEditMenusWithQuit() {
        print("SPIKE: NSApp is nil at probe start: \(NSApp == nil)")
        let menu = AppMainMenu.make()
        #expect(menu.items.count == 2)
        #expect(menu.items.first?.submenu?.items.contains { $0.title == "Quit Slovo" } == true)
    }

    // Stated sensitivity: AppDelegate.makeMenu returning an empty NSMenu() instead of the built menu → RED
    @Test
    func delegateBuildsDictationMenu() throws {
        let suite = "com.slovo.app.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(
            logger: Logger(subsystem: "com.slovo.app.tests", category: "spike"),
            defaults: defaults,
            fnKeyAssignmentReader: NoFnKeyAssignment(),
            openRouterKeyProvider: KeychainOpenRouterKeyProvider(
                readKey: { nil },
                keyExists: { false },
                writeKey: { _ in },
                deleteKey: {}
            ),
            personalization: nil
        )
        let state = delegate.store.state
        let menu = delegate.makeMenu(
            state.dictationMenuInput,
            rows: DictationMenuRows(statusLine: state.statusLineText, isFnKeySystemAssigned: state.isFnKeySystemAssigned),
            indication: state.updateIndication,
            muteAvailability: state.outputMuteAvailability,
            inputDeviceChoice: state.inputDeviceChoice
        )
        #expect(!menu.items.isEmpty)
    }

    // Stated sensitivity: removing reduce(.checkStarted) from updater(_:mayPerform:) → RED
    @Test
    func updaterGateMarksCheckStarted() throws {
        let suite = "com.slovo.app.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults)
        let coordinator = UpdaterCoordinator(
            store: store,
            onUpdaterEvent: {},
            onInstallFailedAfterRestart: {}
        )
        #expect(store.state.updateIndication == .idle)
        try coordinator.updater(coordinator.updater, mayPerform: .updatesInBackground)
        #expect(store.state.updateIndication == .checking)
    }
}
