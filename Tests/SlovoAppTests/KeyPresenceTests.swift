import AppKit
import Testing
@testable import slovo
@testable import SlovoCore

/// Key presence in the store, read from the app-owned key provider: at launch and
/// after every Settings save or removal.
@MainActor
@Suite("Key presence")
struct KeyPresenceTests {
    /// Counts the store's publications. The store calls its listeners on the main actor.
    private final class Publications {
        var calls = 0
    }

    /// The launch seed reads key presence from the injected provider: a provider with
    /// a key gives cleanup on, one without gives the no-key state.
    /// Stated sensitivity: the seed is fixed to true or to false, is read elsewhere,
    /// or the delegate ignores the injected provider and builds its own → RED. Both
    /// delegates are needed: the real provider reads the real Keychain, which cannot
    /// match both.
    @Test
    func launchSeedsKeyPresenceFromTheInjectedProvider() {
        let withKey = AppShellFixture(isKeyStored: true)
        let withoutKey = AppShellFixture(isKeyStored: false)

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
        let shell = AppShellFixture(isKeyStored: false)

        shell.app.saveOpenRouterKey("test-key-1")
        #expect(shell.store.state.isOpenRouterKeyPresent)

        shell.keychain.failWrites()
        shell.app.saveOpenRouterKey("test-key-2")
        #expect(!shell.store.state.isOpenRouterKeyPresent)

        shell.keychain.allowWrites()
        shell.app.saveOpenRouterKey("test-key-3")
        #expect(shell.store.state.isOpenRouterKeyPresent)
        shell.app.removeOpenRouterKey()
        #expect(!shell.store.state.isOpenRouterKeyPresent)

        shell.app.saveOpenRouterKey("test-key-4")
        shell.keychain.failDeletes()
        shell.app.removeOpenRouterKey()
        #expect(shell.store.state.isOpenRouterKeyPresent)
    }

    /// Removing a key calls the provider's delete once and writes presence and the
    /// cleanup scope in one store update. With cleanup on, `.keyRemoved` adds one to
    /// the scope generation (`CleanupScopeReducer.reduce`) and the availability change
    /// to off adds one more, so +2. A failed delete publishes nothing and keeps the
    /// generation.
    /// Stated sensitivity: the delete is dropped or called twice, the `.keyRemoved`
    /// event or the scope application is dropped (+1), the event is applied on the
    /// failure path too, presence is written before the delete, written from another
    /// source or split into two store updates → RED.
    @Test
    func removingAKeyWritesPresenceAndScopeInOneUpdate() {
        let removed = AppShellFixture(isKeyStored: true)
        let removedPublications = Publications()
        let removedBefore = removed.store.state.cleanupScope.generation
        removed.store.listen({ $0 }, { _ in removedPublications.calls += 1 })

        removed.app.removeOpenRouterKey()

        #expect(removed.keychain.deleteCalls == 1)
        #expect(!removed.store.state.isOpenRouterKeyPresent)
        #expect(removed.store.state.cleanupScope.generation == removedBefore + 2)
        #expect(removedPublications.calls == 1)

        let kept = AppShellFixture(isKeyStored: true)
        let keptPublications = Publications()
        let keptBefore = kept.store.state.cleanupScope.generation
        kept.keychain.failDeletes()
        kept.store.listen({ $0 }, { _ in keptPublications.calls += 1 })

        kept.app.removeOpenRouterKey()

        #expect(kept.keychain.deleteCalls == 1)
        #expect(kept.store.state.isOpenRouterKeyPresent)
        #expect(kept.store.state.cleanupScope.generation == keptBefore)
        #expect(keptPublications.calls == 0)
    }
}
