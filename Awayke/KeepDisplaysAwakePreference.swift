import Foundation

final class KeepDisplaysAwakePreference {
    private static let defaultsKey = "keepDisplaysAwake"
    private static let defaultValue = true

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.defaultsKey: Self.defaultValue])
    }

    var value: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}
