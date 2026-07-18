import SlovoCore

/// An `UpdaterSwitch` fake that records the full assignment sequence to
/// `automaticallyChecksForUpdates`, so a test can pin the exact activation calls —
/// e.g. off must produce exactly `[false]`, the zero-update-network invariant.
public final class FakeUpdaterSwitch: UpdaterSwitch {
    /// Every value assigned to `automaticallyChecksForUpdates`, in order. The
    /// initial value is not recorded (only explicit assignments append), so the
    /// array is exactly the activation calls a test drove.
    public private(set) var assignments: [Bool] = []

    public init() {}

    public var automaticallyChecksForUpdates = false {
        didSet { assignments.append(automaticallyChecksForUpdates) }
    }
}
