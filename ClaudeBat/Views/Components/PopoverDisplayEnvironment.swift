import Foundation
import SwiftUI

/// Display-only inputs that make popover strings deterministic in layout tests.
/// Production uses the live clock and the user's current timezone.
public struct PopoverDisplayEnvironment: Equatable, Sendable {
    public let fixedNow: Date?
    public let timeZone: TimeZone
    public let claudeInstalled: Bool?

    public init(
        fixedNow: Date? = nil,
        timeZone: TimeZone = .current,
        claudeInstalled: Bool? = nil
    ) {
        self.fixedNow = fixedNow
        self.timeZone = timeZone
        self.claudeInstalled = claudeInstalled
    }

    public var now: Date {
        fixedNow ?? Date()
    }
}

private struct PopoverDisplayEnvironmentKey: EnvironmentKey {
    static let defaultValue = PopoverDisplayEnvironment()
}

public extension EnvironmentValues {
    var popoverDisplayEnvironment: PopoverDisplayEnvironment {
        get { self[PopoverDisplayEnvironmentKey.self] }
        set { self[PopoverDisplayEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func popoverDisplayEnvironment(_ environment: PopoverDisplayEnvironment) -> some View {
        self.environment(\.popoverDisplayEnvironment, environment)
    }
}
