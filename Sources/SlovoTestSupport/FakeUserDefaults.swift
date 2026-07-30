import Foundation
import SlovoCore

/// In-memory `UserDefaults` fake keyed by default name. Stores values of any
/// type: AppKit persists the status-item position as a number, so a Data-only
/// fake could not distinguish "key absent" from "key holds a number".
public final class FakeUserDefaults: UserDefaultsWriting {
    private var valuesByKey: [String: Any]

    public init(dataByKey: [String: Data] = [:]) {
        self.valuesByKey = dataByKey
    }

    public func data(forKey defaultName: String) -> Data? {
        valuesByKey[defaultName] as? Data
    }

    public func object(forKey defaultName: String) -> Any? {
        valuesByKey[defaultName]
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        valuesByKey[defaultName] = value
    }
}
