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

    var errorDescription: String? {
        switch self {
        case .creationFailed(let name, let code):
            return "Couldn't create the \(name) wake assertion (IOKit \(code))."
        }
    }
}

final class DisplayWakeKeeper: WakeAssertionControlling {

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0

    func prevent() -> Result<Void, Error> {
        guard systemAssertionID == 0 || displayAssertionID == 0 else {
            return .success(())
        }

        allow()

        let systemResult = IOPMAssertionCreateWithName(
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

        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Awayke is keeping the display awake" as CFString,
            &displayAssertionID
        )
        guard displayResult == kIOReturnSuccess else {
            allow()
            return .failure(WakeAssertionError.creationFailed(
                name: "display-sleep",
                code: displayResult
            ))
        }

        return .success(())
    }

    func allow() {
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
    }

    deinit {
        allow()
    }
}
