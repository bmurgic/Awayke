import Foundation

protocol WakeAssertionControlling: AnyObject {
    func prevent(shouldKeepDisplayAwake: Bool) -> Result<Void, Error>
    func updateDisplayAssertion(
        shouldKeepDisplayAwake: Bool
    ) -> Result<Void, Error>
    func allow()
}

protocol ClamshellSleepControlling: AnyObject {
    func prevent() -> Result<Void, Error>
    func allow() -> Result<Void, Error>
}

protocol SleepFallbackControlling: AnyObject {
    func disableSleep(_ disable: Bool,
                      completion: @escaping (Result<Void, Error>) -> Void)
}

enum WakeModeControllerError: LocalizedError {
    case transitionInProgress

    var errorDescription: String? {
        "Awayke is already changing wake mode."
    }
}

final class WakeModeController {
    private let assertions: WakeAssertionControlling
    private let clamshell: ClamshellSleepControlling
    private let fallback: SleepFallbackControlling

    private(set) var mode = WakeMode.off
    private(set) var shouldKeepDisplayAwake: Bool
    private var isFallbackActive = false
    private var isTransitioning = false

    init(assertions: WakeAssertionControlling,
         clamshell: ClamshellSleepControlling,
         fallback: SleepFallbackControlling,
         shouldKeepDisplayAwake: Bool = true) {
        self.assertions = assertions
        self.clamshell = clamshell
        self.fallback = fallback
        self.shouldKeepDisplayAwake = shouldKeepDisplayAwake
    }

    func apply(_ target: WakeMode,
               completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isTransitioning else {
            completion(.failure(WakeModeControllerError.transitionInProgress))
            return
        }
        guard target != mode else {
            completion(.success(()))
            return
        }

        isTransitioning = true
        switch target {
        case .off:
            turnOff(completion: completion)
        case .openLid:
            activateOpenLid(completion: completion)
        case .lidClosed:
            activateLidClosed(completion: completion)
        }
    }

    func setShouldKeepDisplayAwake(
        _ shouldKeepDisplayAwake: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !isTransitioning else {
            completion(.failure(WakeModeControllerError.transitionInProgress))
            return
        }
        guard shouldKeepDisplayAwake != self.shouldKeepDisplayAwake else {
            completion(.success(()))
            return
        }
        guard mode.isActive else {
            self.shouldKeepDisplayAwake = shouldKeepDisplayAwake
            completion(.success(()))
            return
        }

        isTransitioning = true
        switch assertions.updateDisplayAssertion(
            shouldKeepDisplayAwake: shouldKeepDisplayAwake
        ) {
        case .success:
            self.shouldKeepDisplayAwake = shouldKeepDisplayAwake
            isTransitioning = false
            completion(.success(()))
        case .failure(let error):
            isTransitioning = false
            completion(.failure(error))
        }
    }

    private func activateOpenLid(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch mode {
        case .off:
            switch assertions.prevent(
                shouldKeepDisplayAwake: shouldKeepDisplayAwake
            ) {
            case .success:
                finish(mode: .openLid, completion: completion)
            case .failure(let error):
                finish(error: error, completion: completion)
            }
        case .openLid:
            finish(mode: .openLid, completion: completion)
        case .lidClosed:
            leaveLidClosedMode(target: .openLid, completion: completion)
        }
    }

    private func activateLidClosed(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let previousMode = mode
        if previousMode == .off {
            if case .failure(let error) = assertions.prevent(
                shouldKeepDisplayAwake: shouldKeepDisplayAwake
            ) {
                finish(error: error, completion: completion)
                return
            }
        }

        switch clamshell.prevent() {
        case .success:
            isFallbackActive = false
            finish(mode: .lidClosed, completion: completion)
        case .failure:
            _ = clamshell.allow()
            fallback.disableSleep(true) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.isFallbackActive = true
                    self.finish(mode: .lidClosed, completion: completion)
                case .failure(let error):
                    if previousMode == .off {
                        self.assertions.allow()
                    }
                    self.finish(error: error, completion: completion)
                }
            }
        }
    }

    private func turnOff(completion: @escaping (Result<Void, Error>) -> Void) {
        guard mode != .off else {
            finish(mode: .off, completion: completion)
            return
        }

        if isFallbackActive {
            fallback.disableSleep(false) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.isFallbackActive = false
                    self.assertions.allow()
                    self.finish(mode: .off, completion: completion)
                case .failure(let error):
                    self.finish(error: error, completion: completion)
                }
            }
            return
        }

        if mode == .lidClosed {
            if case .failure(let error) = clamshell.allow() {
                finish(error: error, completion: completion)
                return
            }
        }
        assertions.allow()
        finish(mode: .off, completion: completion)
    }

    private func leaveLidClosedMode(
        target: WakeMode,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if isFallbackActive {
            fallback.disableSleep(false) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.isFallbackActive = false
                    self.finish(mode: target, completion: completion)
                case .failure(let error):
                    self.finish(error: error, completion: completion)
                }
            }
            return
        }

        switch clamshell.allow() {
        case .success:
            finish(mode: target, completion: completion)
        case .failure(let error):
            finish(error: error, completion: completion)
        }
    }

    private func finish(mode: WakeMode,
                        completion: @escaping (Result<Void, Error>) -> Void) {
        self.mode = mode
        isTransitioning = false
        completion(.success(()))
    }

    private func finish(error: Error,
                        completion: @escaping (Result<Void, Error>) -> Void) {
        isTransitioning = false
        completion(.failure(error))
    }
}
