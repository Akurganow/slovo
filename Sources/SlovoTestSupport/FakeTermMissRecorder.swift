import SlovoCore

/// Records every batch handed to `recordMisses`, in order.
public actor FakeTermMissRecorder: TermMissRecording {
    public private(set) var batches: [[String]] = []

    public init() {}

    public func recordMisses(_ termKeys: [String]) async {
        batches.append(termKeys)
    }

    public func recordedBatches() -> [[String]] { batches }
}

/// Blocks inside `recordMisses` until released — proves the hot path never
/// awaits the recording task.
public actor BlockingTermMissRecorder: TermMissRecording {
    private var release: CheckedContinuation<Void, Never>?
    private var isReleased = false

    public init() {}

    public func recordMisses(_ termKeys: [String]) async {
        if isReleased { return }
        await withCheckedContinuation { continuation in
            release = continuation
        }
    }

    public func releaseRecording() {
        isReleased = true
        release?.resume()
        release = nil
    }
}
