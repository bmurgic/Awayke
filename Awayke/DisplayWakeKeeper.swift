//
//  DisplayWakeKeeper.swift
//  Awayke
//
//  Holds ordinary IOPM assertions while Awayke is active. These keep an open
//  Mac awake without changing the separate lid-close sleep policy.
//

import Foundation
import IOKit.pwr_mgt

enum WakeAssertionError: LocalizedError {
    case creationFailed(name: String, code: IOReturn)
    case releaseFailed(name: String, code: IOReturn)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let name, let code):
            return "Couldn't create the \(name) wake assertion (IOKit \(code))."
        case .releaseFailed(let name, let code):
            return "Couldn't release the \(name) wake assertion (IOKit \(code))."
        }
    }
}

final class DisplayWakeKeeper: WakeAssertionControlling {

    typealias AssertionCreator = (
        CFString,
        IOPMAssertionLevel,
        CFString,
        UnsafeMutablePointer<IOPMAssertionID>
    ) -> IOReturn
    typealias AssertionReleaser = (IOPMAssertionID) -> IOReturn

    private let createAssertion: AssertionCreator
    private let releaseAssertion: AssertionReleaser
    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0

    init(
        createAssertion: @escaping AssertionCreator = IOPMAssertionCreateWithName,
        releaseAssertion: @escaping AssertionReleaser = IOPMAssertionRelease
    ) {
        self.createAssertion = createAssertion
        self.releaseAssertion = releaseAssertion
    }

    func prevent(
        shouldKeepDisplayAwake: Bool
    ) -> Result<Void, Error> {
        if systemAssertionID == 0 {
            let systemResult = createAssertion(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Awayke is keeping the Mac awake" as CFString,
                &systemAssertionID
            )
            guard systemResult == kIOReturnSuccess else {
                systemAssertionID = 0
                return .failure(WakeAssertionError.creationFailed(
                    name: "system-sleep",
                    code: systemResult
                ))
            }
        }

        let displayResult = updateDisplayAssertion(
            shouldKeepDisplayAwake: shouldKeepDisplayAwake
        )
        guard case .success = displayResult else {
            allow()
            return displayResult
        }
        return .success(())
    }

    func updateDisplayAssertion(
        shouldKeepDisplayAwake: Bool
    ) -> Result<Void, Error> {
        guard shouldKeepDisplayAwake else {
            return releaseDisplayAssertion()
        }
        guard systemAssertionID != 0, displayAssertionID == 0 else {
            return .success(())
        }

        let displayResult = createAssertion(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Awayke is keeping the display awake" as CFString,
            &displayAssertionID
        )
        guard displayResult == kIOReturnSuccess else {
            displayAssertionID = 0
            return .failure(WakeAssertionError.creationFailed(
                name: "display-sleep",
                code: displayResult
            ))
        }
        return .success(())
    }

    func allow() {
        _ = releaseDisplayAssertion()
        if systemAssertionID != 0 {
            if releaseAssertion(systemAssertionID) == kIOReturnSuccess {
                systemAssertionID = 0
            }
        }
    }

    private func releaseDisplayAssertion() -> Result<Void, Error> {
        guard displayAssertionID != 0 else { return .success(()) }
        let result = releaseAssertion(displayAssertionID)
        guard result == kIOReturnSuccess else {
            return .failure(WakeAssertionError.releaseFailed(
                name: "display-sleep",
                code: result
            ))
        }
        displayAssertionID = 0
        return .success(())
    }

    deinit {
        allow()
    }
}
