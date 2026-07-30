import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The key strings and the seed value below are intentionally literal, not derived
// from the production constants: AppKit silently ignores an unknown defaults key, so
// a typo in the constant must fail HERE instead of passing self-consistently, and the
// seed value pins the chosen policy instead of echoing whatever the constant holds.
@Suite("Status-item placement seeding")
struct StatusItemPlacementTests {
    /// A first launch has no stored position, so the seed must write one — that
    /// write is the entire fix for the item drowning in the third-party cluster.
    ///
    /// Sensitivity: a seed that never writes (empty body) → RED.
    @Test
    func seedWritesPreferredPositionWhenKeyAbsent() {
        let defaults = FakeUserDefaults()

        StatusItemPlacement.seedPreferredPositionIfAbsent(in: defaults)

        #expect(defaults.object(forKey: "NSStatusItem Preferred Position Slovo") as? Double == 100)
    }

    /// AppKit persists the user's own drag into the same key; the seed runs every
    /// launch and must never stomp it.
    ///
    /// Sensitivity: an unconditional write (seed without the absence check) → RED.
    @Test
    func seedPreservesExistingPositionWhenKeyPresent() {
        let defaults = FakeUserDefaults()
        defaults.set(342.5, forKey: "NSStatusItem Preferred Position Slovo")

        StatusItemPlacement.seedPreferredPositionIfAbsent(in: defaults)

        #expect(defaults.object(forKey: "NSStatusItem Preferred Position Slovo") as? Double == 342.5)
    }

    /// The key must be the exact unofficial AppKit spelling AND derive from the
    /// autosave name, or the seed lands in a key AppKit never reads.
    ///
    /// Sensitivity: any typo in the prefix or name, or deriving the key from a
    /// different string than the autosave name → RED.
    @Test
    func preferredPositionKeyUsesExactAppKitPrefixAndName() {
        #expect(StatusItemPlacement.preferredPositionKey == "NSStatusItem Preferred Position Slovo")
        #expect(
            StatusItemPlacement.preferredPositionKey
                == "NSStatusItem Preferred Position " + StatusItemPlacement.autosaveName
        )
    }
}
