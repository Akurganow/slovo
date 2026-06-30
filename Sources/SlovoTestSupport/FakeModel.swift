import Foundation
import SlovoCore

/// A `ModelLoading` spy that records load/release without a real model.
public final class FakeModel: ModelLoading {
    public private(set) var loadCount = 0
    public private(set) var releaseCount = 0
    private var loaded = false

    public var isLoaded: Bool { loaded }

    public init() {}

    public func load() async throws {
        loadCount += 1
        loaded = true
    }

    public func release() {
        releaseCount += 1
        loaded = false
    }
}
