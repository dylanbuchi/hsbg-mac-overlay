import Foundation

/// Overlay settings kept in UserDefaults. Injectable (any suite), so the storage can move to a
/// Settings window later without touching the model.
struct OverlayPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let showsCardInCombatKey = "showsCardInCombat"

    /// The NEXT OPPONENT card also shows during combat. Off by default.
    var showsCardInCombat: Bool {
        get { defaults.bool(forKey: Self.showsCardInCombatKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.showsCardInCombatKey) }
    }
}
