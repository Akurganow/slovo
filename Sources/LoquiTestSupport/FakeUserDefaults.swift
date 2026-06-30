import Foundation
import LoquiCore

/// In-memory `UserDefaultsReading` fake keyed by default name.
public struct FakeUserDefaults: UserDefaultsReading {
    private let dataByKey: [String: Data]

    public init(dataByKey: [String: Data] = [:]) {
        self.dataByKey = dataByKey
    }

    public func data(forKey defaultName: String) -> Data? {
        dataByKey[defaultName]
    }
}
