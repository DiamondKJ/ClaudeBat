import Foundation

public struct RecoveryStateStore: RecoveryStatePersisting {
    private let defaults: UserDefaults
    private static let key = "authRecoverySnapshot"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func read() -> RecoverySnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
    }

    public func write(_ snapshot: RecoverySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
