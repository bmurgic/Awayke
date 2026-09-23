//
//  AutoOffTimer.swift
//  Awayke
//
//  Wall-clock countdown behind the "keep awayke for N minutes" presets.
//  Deadline-based rather than interval-based, so the countdown stays
//  honest if the machine sleeps and wakes mid-timer.
//

import Foundation

final class AutoOffTimer {

    /// Called on the main run loop once the deadline has passed.
    var onExpire: (() -> Void)?
    /// Called on the main run loop on each tick while running, so the
    /// UI can redraw the remaining time.
    var onTick: (() -> Void)?

    private(set) var deadline: Date?
    /// The length the running countdown was started with.
    private(set) var minutes: Int?
    private var ticker: Timer?

    var isRunning: Bool { deadline != nil }

    /// Seconds left, or nil when no countdown is running.
    var remaining: TimeInterval? {
        guard let deadline else { return nil }
        return max(0, deadline.timeIntervalSinceNow)
    }

    func start(minutes: Int) {
        cancel()
        self.minutes = minutes
        deadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)

        let ticker = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common modes so the countdown keeps ticking while the menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        minutes = nil
    }

    private func tick() {
        guard let deadline else { return }
        guard Date() >= deadline else {
            onTick?()
            return
        }
        cancel()
        onExpire?()
    }
}
