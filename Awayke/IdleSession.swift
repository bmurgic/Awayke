//
//  IdleSession.swift
//  Awayke
//
//  Behind the "until idle for N minutes" presets. Polls the system's
//  time-since-last-input and expires once it reaches the chosen length.
//  A closed lid produces no input, so the wait keeps running with the lid
//  shut; an external keyboard or mouse still resets it.
//

import CoreGraphics
import Foundation

final class IdleSession {

    /// Called on the main run loop once the user has been idle long enough,
    /// with the session's length in minutes.
    var onExpire: ((Int) -> Void)?

    private(set) var idleMinutes: Int?
    private let idleSeconds: () -> TimeInterval
    private var ticker: Timer?

    var isActive: Bool { idleMinutes != nil }

    /// - Parameter idleSeconds: Seconds since the last keyboard or mouse
    ///   input. Injectable for tests.
    init(idleSeconds: @escaping () -> TimeInterval = IdleSession.systemIdleSeconds) {
        self.idleSeconds = idleSeconds
    }

    /// Reads HID idle time without Accessibility permission. Awayke's own
    /// power assertions do not reset it.
    static func systemIdleSeconds() -> TimeInterval {
        // ~0 is kCGAnyInputEventType, which Swift does not import.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    func start(minutes: Int) {
        cancel()
        idleMinutes = minutes

        let ticker = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.check()
        }
        // Common modes so the check keeps running while the menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        idleMinutes = nil
    }

    func check() {
        guard let idleMinutes else { return }
        guard idleSeconds() >= TimeInterval(idleMinutes) * 60 else { return }
        cancel()
        onExpire?(idleMinutes)
    }
}
