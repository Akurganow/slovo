import SlovoCore
import SwiftUI

extension AppStore {
    /// A two-way binding to one `Config` field: reads the state, writes through
    /// `update`.
    func binding<Value>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { self.state.config[keyPath: keyPath] },
            set: { value in self.update { $0.config[keyPath: keyPath] = value } }
        )
    }
}
