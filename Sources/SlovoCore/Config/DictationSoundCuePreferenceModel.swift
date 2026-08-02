import Combine

/// The observable app-layer projection of the Sound Cues preference.
///
/// The app's apply path is its single writer. Settings observes this object
/// instead of retaining a snapshot, so a menu-bar change is visible immediately.
@preconcurrency
@MainActor
public final class DictationSoundCuePreferenceModel: ObservableObject {
    @Published public private(set) var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Publishes an already-persisted preference change synchronously.
    public func update(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
