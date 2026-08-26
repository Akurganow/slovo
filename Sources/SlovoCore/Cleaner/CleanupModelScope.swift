/// The set of model ids the saved OpenRouter key may call (spec rev 3 §4).
/// `.unknown` covers: no fetch yet, no key, cleanup off, fetch failed.
public enum CleanupModelScope: Equatable, Sendable {
    case unknown
    case known(Set<String>)
}

/// The K2 derivation: preference × catalog × scope → what the pickers show and
/// what the pipeline uses. Pure; the stored preference is never rewritten (K1) —
/// callers pass it in and persist it elsewhere.
public enum CleanupModelSelection {
    public enum Note: Equatable, Sendable {
        case substitution(preferred: String, effective: String)
        case customOutsideScope
    }

    public struct Result: Equatable, Sendable {
        /// Catalog ∩ scope in catalog declaration order (full catalog when the
        /// scope is unknown or degenerate). The menu-bar submenu shows exactly this.
        public let options: [CleanupModelOption]
        /// The stored non-catalog id, when there is one: the Settings picker
        /// appends it as its extra row; the menu does not (K3).
        public let customRow: CleanupModelOption?
        public let effective: String
        public let note: Note?

        public init(options: [CleanupModelOption], customRow: CleanupModelOption?, effective: String, note: Note?) {
            self.options = options
            self.customRow = customRow
            self.effective = effective
            self.note = note
        }
    }

    public static func derive(
        preference: String,
        catalog: [CleanupModelOption],
        scope: CleanupModelScope
    ) -> Result {
        let isCustom = !catalog.contains { $0.id == preference }
        let customRow = isCustom ? CleanupModelOption(id: preference, displayName: preference) : nil
        let failOpen = Result(options: catalog, customRow: customRow, effective: preference, note: nil)
        guard case .known(let ids) = scope else { return failOpen }
        let available = catalog.filter { ids.contains($0.id) }
        // A scope that would empty the picker is degenerate — same as .unknown (K5).
        guard !available.isEmpty else { return failOpen }
        if isCustom {
            let note: Note? = ids.contains(preference) ? nil : .customOutsideScope
            return Result(options: available, customRow: customRow, effective: preference, note: note)
        }
        if ids.contains(preference) {
            return Result(options: available, customRow: nil, effective: preference, note: nil)
        }
        let effective = ids.contains(Config.defaultOpenRouterModel)
            ? Config.defaultOpenRouterModel
            : available[0].id
        return Result(
            options: available, customRow: nil, effective: effective,
            note: .substitution(preferred: preference, effective: effective)
        )
    }
}
