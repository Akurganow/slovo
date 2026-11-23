import AppKit
import SlovoTestSupport
import Testing
@testable import slovo
@testable import SlovoCore

/// Key presence in the store, read from the app-owned key provider: at launch and
/// after every Settings save or removal.
@MainActor
@Suite("Key presence")
struct KeyPresenceTests {
    /// The states the store published, in order. The store calls its listeners on the main actor.
    private final class Publications {
        var states: [AppState] = []
    }

    /// The launch seed reads key presence from the injected provider: a provider with
    /// a key gives cleanup on, one without gives the no-key state.
    /// Stated sensitivity: the seed is fixed to true or to false, is read elsewhere,
    /// or the delegate ignores the injected provider and builds its own → RED. Both
    /// delegates are needed: the real provider reads the real Keychain, which cannot
    /// match both.
    @Test
    func launchSeedsKeyPresenceFromTheInjectedProvider() {
        let withKey = TestAppDelegate(isKeyStored: true)
        let withoutKey = TestAppDelegate(isKeyStored: false)

        #expect(withKey.store.state.isOpenRouterKeyPresent)
        #expect(withKey.store.state.cleanupAvailability == .on)
        #expect(!withoutKey.store.state.isOpenRouterKeyPresent)
        #expect(withoutKey.store.state.cleanupAvailability == .offNoKey)
    }

    /// A save and a removal write key presence read back from the provider on both
    /// outcomes. The delegate has no composition, so a read through the pipeline
    /// finds nothing. A failed save leaves no key (the real write removes the old item
    /// first) and a failed removal keeps it.
    /// Stated sensitivity: the Settings write reads presence through the composition
    /// or from anything but the provider, is dropped or fixed, is skipped after a
    /// failed save, or writes false after a failed removal → RED.
    @Test
    func savingAndRemovingAKeyWritesPresenceFromTheProvider() {
        let shell = TestAppDelegate(isKeyStored: false)

        shell.appUnderTest.saveOpenRouterKey("test-key-1")
        #expect(shell.store.state.isOpenRouterKeyPresent)

        shell.keychain.failWrites()
        shell.appUnderTest.saveOpenRouterKey("test-key-2")
        #expect(!shell.store.state.isOpenRouterKeyPresent)

        shell.keychain.allowWrites()
        shell.appUnderTest.saveOpenRouterKey("test-key-3")
        #expect(shell.store.state.isOpenRouterKeyPresent)
        shell.appUnderTest.removeOpenRouterKey()
        #expect(!shell.store.state.isOpenRouterKeyPresent)

        shell.appUnderTest.saveOpenRouterKey("test-key-4")
        shell.keychain.failDeletes()
        shell.appUnderTest.removeOpenRouterKey()
        #expect(shell.store.state.isOpenRouterKeyPresent)
    }

    /// Removing a key calls the provider's delete once and writes presence and the
    /// cleanup scope in one store update. With cleanup on, the launch reconcile makes
    /// generation 1 (`AppState.reconciled`); `.keyRemoved` adds one
    /// (`CleanupScopeReducer.reduce`) and the availability change to off adds one more,
    /// so generation 3. A failed delete publishes nothing and keeps generation 1.
    /// Stated sensitivity: the delete is dropped or called twice, the `.keyRemoved`
    /// event or the scope application is dropped (generation 2), the event is applied
    /// on the failure path too, presence is written before the delete, written from
    /// another source or split into two store updates → RED.
    @Test
    func removingAKeyWritesPresenceAndScopeInOneUpdate() {
        let removed = TestAppDelegate(isKeyStored: true)
        let removedPublications = Publications()
        #expect(removed.store.state.cleanupScope.generation == 1)
        removed.store.listen({ $0 }, { removedPublications.states.append($0) })

        removed.appUnderTest.removeOpenRouterKey()

        #expect(removed.keychain.deleteCalls == 1)
        #expect(!removed.store.state.isOpenRouterKeyPresent)
        #expect(removed.store.state.cleanupScope.generation == 3)
        #expect(removedPublications.states.count == 1)

        let kept = TestAppDelegate(isKeyStored: true)
        let keptPublications = Publications()
        kept.keychain.failDeletes()
        kept.store.listen({ $0 }, { keptPublications.states.append($0) })

        kept.appUnderTest.removeOpenRouterKey()

        #expect(kept.keychain.deleteCalls == 1)
        #expect(kept.store.state.isOpenRouterKeyPresent)
        #expect(kept.store.state.cleanupScope.generation == 1)
        #expect(keptPublications.states.isEmpty)
    }

    /// The delegate serves one store: two reads give the same object, and a write
    /// through the `SettingsActions` seam the panes use shows on the delegate's store.
    /// Stated sensitivity: `store` becomes a computed property that builds a new store
    /// on every read → RED on the identity check and on the write check.
    @Test
    func theDelegateServesOneStore() {
        let shell = TestAppDelegate()
        let actions: any SettingsActions = shell.appUnderTest
        let before = shell.appUnderTest.store.state.config.playsDictationSoundCues

        actions.store.update { $0.config.playsDictationSoundCues = !before }

        let firstRead = shell.appUnderTest.store
        let secondRead = shell.appUnderTest.store
        #expect(firstRead === secondRead)
        #expect(actions.store === shell.appUnderTest.store)
        #expect(shell.appUnderTest.store.state.config.playsDictationSoundCues == !before)
    }
}
