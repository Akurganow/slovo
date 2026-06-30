import Foundation
import SlovoCore

/// In-memory `UserDefaults` fake keyed by default name.
public final class FakeUserDefaults: UserDefaultsWriting {
    private var dataByKey: [String: Data]

    public init(dataByKey: [String: Data] = [:]) {
        self.dataByKey = dataByKey
    }

    public func data(forKey defaultName: String) -> Data? {
        dataByKey[defaultName]
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        dataByKey[defaultName] = value as? Data
    }
}
