# Logic: where a defect costs most here

Facts of this repository that a correctness review needs. Its readers are
whoever reviews code for a wrong result, a crash, a race or corrupted state.
Take the module list from `Package.swift`, never from a list written here.

## Code with real consequences

- the dictation pipeline from key down to insertion;
- the guard that keeps an empty transcript from the cleanup provider and the
  pasteboard;
- the sound-cue queue and its release deadline;
- mute and restore;
- the Keychain;
- the update engine's states;
- decoding the cleanup provider's response;
- the encrypted personalization database;
- the Objective-C exception boundary.

Code that writes a stored record, such as the personalization database or the
stored settings, weighs most. A defect there falsifies everything built on
it.

Concurrency covers actor isolation, task lifetimes, cancellation, and
ordering between a key event and work already in flight. Around a shim at a
foreign boundary, read the callers of `SlovoObjC` and of the system
frameworks, not the shim itself.

## Swift constructs that bypass the checks

- force unwraps, `try!`, `as!`, `unowned`, `fatalError` and
  `preconditionFailure`;
- against the concurrency checks, `@unchecked Sendable`,
  `nonisolated(unsafe)` and `assumeIsolated`;
- hand-written `==`, `<` and `hash(into:)`;
- comments saying "hack", "TODO", "for now", "should be fine" or "assume".

An escape hatch with a written invariant or an explicit suppression beside it
is a recorded reason.

## Entry points

A reachability trace starts at the entry of an executable target in
`Package.swift`, or at a callback the app hands the system: the key event
tap, a menu or Settings action, a notification or an update-engine callback.

## Behaviour kept on purpose

Settings stored by earlier releases keep decoding. An absent field takes its
default, and the key trigger's stored values predate the split by key side.
The comments in `Sources/SlovoCore/Config/Config.swift` and
`Sources/SlovoCore/Config/ConfigStore.swift` record it. There is no
migration.

This file describes the tree. Where the tree and this file disagree, the
tree wins and this file is stale.
