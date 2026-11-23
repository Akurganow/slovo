import AppKit
import SlovoTestSupport
import Synchronization
import os
@testable import slovo
@testable import SlovoCore

/// The Keychain's one item as a flag the tests own. A save sets it, a delete
/// clears it, and each of the two can be made to throw. A failing save clears
/// the flag, as the real write removes the old item before it adds the new one
/// (`KeychainOpenRouterKeyProvider.store`); a failing delete keeps it.
final class FakeKeychainItem: Sendable {
    struct Failure: Error {}

    private struct State {
        var isStored: Bool
        var writeFails = false
        var deleteFails = false
        var deleteCalls = 0
    }

    private let state: Mutex<State>

    init(isStored: Bool) {
        state = Mutex(State(isStored: isStored))
    }

    private var isStored: Bool { state.withLock { $0.isStored } }
    var deleteCalls: Int { state.withLock { $0.deleteCalls } }

    func failWrites() { state.withLock { $0.writeFails = true } }
    func failDeletes() { state.withLock { $0.deleteFails = true } }
    func allowWrites() { state.withLock { $0.writeFails = false } }

    func write() throws {
        try state.withLock {
            $0.isStored = false
            if $0.writeFails { throw Failure() }
            $0.isStored = true
        }
    }

    func delete() throws {
        try state.withLock {
            $0.deleteCalls += 1
            if $0.deleteFails { throw Failure() }
            $0.isStored = false
        }
    }

    /// A key provider whose four closures run over this item.
    func makeProvider() -> KeychainOpenRouterKeyProvider {
        KeychainOpenRouterKeyProvider(
            readKey: { [self] in isStored ? "test-key" : nil },
            keyExists: { [self] in isStored },
            writeKey: { [self] _ in try write() },
            deleteKey: { [self] in try delete() }
        )
    }
}

struct FixedFnKeyAssignmentReader: FnKeyAssignmentReading {
    let isFnKeySystemAssigned: Bool
}

/// An `AppDelegate` built from fakes: in-memory defaults, a key provider over
/// `FakeKeychainItem`, no personalization database and a fixed fn verdict. It has
/// no status item and no composition; no test launches it.
@MainActor
final class AppShellFixture {
    let app: AppDelegate
    let keychain: FakeKeychainItem

    init(isKeyStored: Bool = true) {
        keychain = FakeKeychainItem(isStored: isKeyStored)
        app = AppDelegate(
            logger: Logger(subsystem: "com.slovo.tests", category: "shell"),
            defaults: FakeUserDefaults(),
            fnKeyAssignmentReader: FixedFnKeyAssignmentReader(isFnKeySystemAssigned: false),
            openRouterKeyProvider: keychain.makeProvider(),
            personalization: nil
        )
    }

    var store: AppStore { app.store }

    /// The dictation menu for the store's current state.
    func buildMenu(statusLine: String = "Hold fn to talk", isFnKeySystemAssigned: Bool = false) -> DictationMenuBuilder.Built {
        DictationMenuBuilder(target: app).make(
            store.state.dictationMenuInput,
            rows: DictationMenuRows(statusLine: statusLine, isFnKeySystemAssigned: isFnKeySystemAssigned)
        )
    }
}

extension NSMenu {
    /// The top-level item with exactly this title.
    func item(exactly title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }

    /// The top-level item whose title starts with `prefix`.
    func item(startingWith prefix: String) -> NSMenuItem? {
        items.first { $0.title.hasPrefix(prefix) }
    }
}

extension NSMenuItem {
    /// Sends the row's action to its target, as a click does.
    func click() {
        guard let action, let target else { return }
        _ = target.perform(action, with: self)
    }
}
