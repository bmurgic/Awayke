import AppKit
import Foundation
import IOKit.pwr_mgt

var failures = 0

func check(_ actual: AutoOffAction, _ expected: AutoOffAction, _ name: String) {
    if actual == expected {
        print("ok - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): got \(actual), expected \(expected)")
    }
}

// threshold 0 disables the feature entirely
check(AutoOffPolicy.decide(intent: true, suspended: false, percent: 5, onAC: false, threshold: 0),
      .none, "threshold 0 disables")

// suspend just below threshold, on battery
check(AutoOffPolicy.decide(intent: true, suspended: false, percent: 19, onAC: false, threshold: 20),
      .suspend, "suspend below threshold on battery")

// no suspend exactly at threshold (strict less-than)
check(AutoOffPolicy.decide(intent: true, suspended: false, percent: 20, onAC: false, threshold: 20),
      .none, "no suspend at exactly threshold")

// never suspend on AC
check(AutoOffPolicy.decide(intent: true, suspended: false, percent: 5, onAC: true, threshold: 20),
      .none, "no suspend on AC")

// never suspend when the user hasn't turned Awayke on
check(AutoOffPolicy.decide(intent: false, suspended: false, percent: 5, onAC: false, threshold: 20),
      .none, "no suspend when intent off")

// resume at threshold + hysteresis, on AC
check(AutoOffPolicy.decide(intent: true, suspended: true, percent: 25, onAC: true, threshold: 20),
      .resume, "resume at threshold+hysteresis on AC")

// no resume below hysteresis band
check(AutoOffPolicy.decide(intent: true, suspended: true, percent: 24, onAC: true, threshold: 20),
      .none, "no resume below hysteresis")

// resume requires AC even when charge is high
check(AutoOffPolicy.decide(intent: true, suspended: true, percent: 30, onAC: false, threshold: 20),
      .none, "no resume on battery")

// a manual override suppresses suspend for the rest of the discharge
check(AutoOffPolicy.decide(intent: true, suspended: false, overridden: true, percent: 5, onAC: false, threshold: 20),
      .none, "override suppresses suspend")

// the override does not block a later resume once back on AC
check(AutoOffPolicy.decide(intent: true, suspended: true, overridden: true, percent: 25, onAC: true, threshold: 20),
      .resume, "override does not block resume")

func checkBool(_ actual: Bool, _ expected: Bool, _ name: String) {
    if actual == expected {
        print("ok - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): got \(actual), expected \(expected)")
    }
}

// the override survives while still discharging
checkBool(AutoOffPolicy.shouldKeepOverride(true, onAC: false), true, "override survives on battery")

// reaching AC ends the override, re-arming auto-off for the next discharge
checkBool(AutoOffPolicy.shouldKeepOverride(true, onAC: true), false, "override ends on AC")

// nothing to keep when there was no override
checkBool(AutoOffPolicy.shouldKeepOverride(false, onAC: false), false, "no override stays no override")

let displayPreferenceSuite = "AwaykeTests.keepDisplaysAwake.\(UUID().uuidString)"
let displayPreferenceDefaults = UserDefaults(suiteName: displayPreferenceSuite)!
displayPreferenceDefaults.removePersistentDomain(forName: displayPreferenceSuite)
defer {
    displayPreferenceDefaults.removePersistentDomain(forName: displayPreferenceSuite)
}

let defaultDisplayPreference = KeepDisplaysAwakePreference(
    defaults: displayPreferenceDefaults
)
checkBool(defaultDisplayPreference.value, true,
          "keep-displays-awake preference defaults on")
defaultDisplayPreference.value = false
let reloadedDisplayPreference = KeepDisplaysAwakePreference(
    defaults: displayPreferenceDefaults
)
checkBool(reloadedDisplayPreference.value, false,
          "keep-displays-awake preference persists off")

var nextAssertionID: IOPMAssertionID = 1
var assertionReleaseAttempts: [IOPMAssertionID] = []
var shouldFailDisplayRelease = true
let releaseFailureKeeper = DisplayWakeKeeper(
    createAssertion: { _, _, _, assertionID in
        assertionID.pointee = nextAssertionID
        nextAssertionID += 1
        return kIOReturnSuccess
    },
    releaseAssertion: { assertionID in
        assertionReleaseAttempts.append(assertionID)
        if assertionID == 2, shouldFailDisplayRelease {
            return kIOReturnError
        }
        return kIOReturnSuccess
    }
)
_ = releaseFailureKeeper.prevent(shouldKeepDisplayAwake: true)
var displayReleaseFailureReported = false
if case .failure = releaseFailureKeeper.updateDisplayAssertion(
    shouldKeepDisplayAwake: false
) {
    displayReleaseFailureReported = true
}
checkBool(displayReleaseFailureReported, true,
          "display assertion release failure is reported")
shouldFailDisplayRelease = false
_ = releaseFailureKeeper.updateDisplayAssertion(
    shouldKeepDisplayAwake: false
)
checkBool(assertionReleaseAttempts.filter { $0 == 2 }.count == 2, true,
          "failed display assertion release remains retryable")

// A lid session started while open waits for a close, then expires on open.
let openStart = LidSessionTracker()
openStart.start(lidClosed: false)
checkBool(openStart.isWaitingForClose, true, "open-start lid session waits for close")
checkBool(openStart.handle(lidClosed: false), false, "open state does not immediately expire")
checkBool(openStart.handle(lidClosed: true), false, "lid close arms session end")
checkBool(openStart.isWaitingForClose, false, "closed session now waits for open")
checkBool(openStart.handle(lidClosed: false), true, "lid reopen expires session")
checkBool(openStart.handle(lidClosed: false), false, "lid session expires only once")

// Starting while already closed (for example through an external display)
// should expire on the next open without requiring another close first.
let closedStart = LidSessionTracker()
closedStart.start(lidClosed: true)
checkBool(closedStart.handle(lidClosed: false), true, "closed-start session expires on open")

let cancelled = LidSessionTracker()
cancelled.start(lidClosed: false)
cancelled.cancel()
checkBool(cancelled.handle(lidClosed: true), false, "cancelled lid session ignores close")
checkBool(cancelled.handle(lidClosed: false), false, "cancelled lid session ignores open")

// If IOKit has not produced its initial reading yet, conservatively wait for
// a complete close/open cycle rather than treating the current state as closed.
let unknownStart = LidSessionTracker()
unknownStart.start(lidClosed: nil)
checkBool(unknownStart.isWaitingForClose, true, "unknown-start session waits for close")
checkBool(unknownStart.handle(lidClosed: true), false, "unknown-start close arms session end")
checkBool(unknownStart.handle(lidClosed: false), true, "unknown-start reopen expires session")

func checkWakeMode(_ actual: WakeMode, _ expected: WakeMode, _ name: String) {
    if actual == expected {
        print("ok - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): got \(actual), expected \(expected)")
    }
}

checkWakeMode(WakeMode.off.target(after: .singleClick), .openLid,
              "single click activates open-lid mode")
checkWakeMode(WakeMode.openLid.target(after: .singleClick), .off,
              "single click turns open-lid mode off")
checkWakeMode(WakeMode.lidClosed.target(after: .singleClick), .off,
              "single click turns lid-closed mode off")
checkWakeMode(WakeMode.off.target(after: .doubleClick), .lidClosed,
              "double click activates lid-closed mode")
checkWakeMode(WakeMode.openLid.target(after: .doubleClick), .lidClosed,
              "double click upgrades open-lid mode")
checkWakeMode(WakeMode.lidClosed.target(after: .doubleClick), .off,
              "double click turns lid-closed mode off")

final class ManualClickScheduler {
    private(set) var delay: TimeInterval?
    private(set) var isCancelled = false
    private var action: (() -> Void)?

    func schedule(after delay: TimeInterval,
                  action: @escaping () -> Void) -> ScheduledClick {
        self.delay = delay
        self.action = action
        isCancelled = false
        return ScheduledClick { [weak self] in
            self?.isCancelled = true
        }
    }

    func fire() {
        guard !isCancelled else { return }
        let pendingAction = action
        action = nil
        pendingAction?()
    }
}

let singleClickScheduler = ManualClickScheduler()
let singleClickResolver = StatusClickResolver(
    systemDoubleClickInterval: 0.25,
    schedule: singleClickScheduler.schedule
)
var singleClickActions: [StatusClickAction] = []
singleClickResolver.receive(clickCount: 1) { singleClickActions.append($0) }
checkBool(singleClickActions.isEmpty, true,
          "single click waits for double-click interval")
checkBool(singleClickScheduler.delay == 0.25, true,
          "single click uses configured interval")
singleClickScheduler.fire()
checkBool(singleClickActions == [.singleClick], true,
          "single click resolves after delay")

let zeroIntervalScheduler = ManualClickScheduler()
let zeroIntervalResolver = StatusClickResolver(
    systemDoubleClickInterval: 0,
    schedule: zeroIntervalScheduler.schedule
)
zeroIntervalResolver.receive(clickCount: 1) { _ in }
checkBool(zeroIntervalScheduler.delay == 0.5, true,
          "zero system interval uses safe fallback")

let doubleClickScheduler = ManualClickScheduler()
let doubleClickResolver = StatusClickResolver(
    systemDoubleClickInterval: 0.25,
    schedule: doubleClickScheduler.schedule
)
var doubleClickActions: [StatusClickAction] = []
doubleClickResolver.receive(clickCount: 1) { doubleClickActions.append($0) }
doubleClickResolver.receive(clickCount: 2) { doubleClickActions.append($0) }
checkBool(doubleClickScheduler.isCancelled, true,
          "double click cancels pending single click")
checkBool(doubleClickActions == [.doubleClick], true,
          "double click resolves once")
doubleClickScheduler.fire()
checkBool(doubleClickActions == [.doubleClick], true,
          "cancelled single click stays cancelled")
doubleClickResolver.receive(clickCount: 3) { doubleClickActions.append($0) }
checkBool(doubleClickActions == [.doubleClick], true,
          "third click does not repeat double click")

let repeatedSingleScheduler = ManualClickScheduler()
let repeatedSingleResolver = StatusClickResolver(
    systemDoubleClickInterval: 0.25,
    schedule: repeatedSingleScheduler.schedule
)
var repeatedSingleActions: [StatusClickAction] = []
repeatedSingleResolver.receive(clickCount: 1) {
    repeatedSingleActions.append($0)
}
repeatedSingleResolver.receive(clickCount: 1) {
    repeatedSingleActions.append($0)
}
checkBool(repeatedSingleScheduler.isCancelled, true,
          "second count-one click cancels pending single click")
checkBool(repeatedSingleActions == [.doubleClick], true,
          "two count-one clicks resolve as double click")

let rightClickScheduler = ManualClickScheduler()
var rightClickActions: [StatusClickAction] = []
var contextMenuCount = 0
let rightClickController = StatusItemInteractionController(
    resolver: StatusClickResolver(
        systemDoubleClickInterval: 0.25,
        schedule: rightClickScheduler.schedule
    ),
    onAction: { rightClickActions.append($0) },
    onContextMenu: { contextMenuCount += 1 }
)
rightClickController.receiveLeftClick(count: 1)
rightClickController.receiveRightClick()
rightClickScheduler.fire()
checkBool(rightClickScheduler.isCancelled, true,
          "right click cancels pending single click")
checkBool(rightClickActions.isEmpty, true,
          "right click prevents pending mode change")
checkBool(contextMenuCount == 1, true,
          "right click opens context menu once")

let accessibleScheduler = ManualClickScheduler()
var accessibleActions: [StatusClickAction] = []
let accessibleController = StatusItemInteractionController(
    resolver: StatusClickResolver(
        systemDoubleClickInterval: 0.25,
        schedule: accessibleScheduler.schedule
    ),
    onAction: { accessibleActions.append($0) },
    onContextMenu: {}
)
accessibleController.receiveLeftClick(count: 1)
accessibleController.receiveAccessibleActivation()
accessibleScheduler.fire()
checkBool(accessibleScheduler.isCancelled, true,
          "accessible activation cancels pending mouse click")
checkBool(accessibleActions == [.singleClick], true,
          "accessible activation resolves single click immediately")

enum TestWakeError: Error {
    case failed
}

final class FakeWakeAssertions: WakeAssertionControlling {
    var preventResult: Result<Void, Error> = .success(())
    var updateDisplayResult: Result<Void, Error> = .success(())
    private(set) var preventCount = 0
    private(set) var allowCount = 0
    private(set) var isPreventingSystemIdleSleep = false
    private(set) var isKeepingDisplayAwake = false

    func prevent(shouldKeepDisplayAwake: Bool) -> Result<Void, Error> {
        preventCount += 1
        if case .success = preventResult {
            isPreventingSystemIdleSleep = true
            isKeepingDisplayAwake = shouldKeepDisplayAwake
        }
        return preventResult
    }

    func updateDisplayAssertion(
        shouldKeepDisplayAwake: Bool
    ) -> Result<Void, Error> {
        guard case .success = updateDisplayResult else {
            return updateDisplayResult
        }
        isKeepingDisplayAwake = shouldKeepDisplayAwake
        return .success(())
    }

    func allow() {
        allowCount += 1
        isPreventingSystemIdleSleep = false
        isKeepingDisplayAwake = false
    }
}

final class FakeClamshellSleep: ClamshellSleepControlling {
    var preventResult: Result<Void, Error> = .success(())
    var allowResult: Result<Void, Error> = .success(())
    private(set) var preventCount = 0
    private(set) var allowCount = 0

    func prevent() -> Result<Void, Error> {
        preventCount += 1
        return preventResult
    }

    func allow() -> Result<Void, Error> {
        allowCount += 1
        return allowResult
    }
}

final class FakeSleepFallback: SleepFallbackControlling {
    var enableResult: Result<Void, Error> = .success(())
    var disableResult: Result<Void, Error> = .success(())
    private(set) var calls: [Bool] = []

    func disableSleep(_ disable: Bool,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        calls.append(disable)
        completion(disable ? enableResult : disableResult)
    }
}

func makeWakeController(
    assertions: FakeWakeAssertions = FakeWakeAssertions(),
    clamshell: FakeClamshellSleep = FakeClamshellSleep(),
    fallback: FakeSleepFallback = FakeSleepFallback(),
    shouldKeepDisplayAwake: Bool = true
) -> (WakeModeController, FakeWakeAssertions, FakeClamshellSleep, FakeSleepFallback) {
    let controller = WakeModeController(
        assertions: assertions,
        clamshell: clamshell,
        fallback: fallback,
        shouldKeepDisplayAwake: shouldKeepDisplayAwake
    )
    return (controller, assertions, clamshell, fallback)
}

let openMode = makeWakeController()
openMode.0.apply(.openLid) { _ in }
checkWakeMode(openMode.0.mode, .openLid, "open-lid activation updates applied mode")
checkBool(openMode.1.preventCount == 1, true, "open-lid activation starts assertions")
checkBool(openMode.1.isKeepingDisplayAwake, true,
          "open-lid mode keeps displays awake by default")
checkBool(openMode.2.preventCount == 0, true, "open-lid activation leaves clamshell sleep alone")
checkBool(openMode.3.calls.isEmpty, true, "open-lid activation does not use fallback")
openMode.0.apply(.off) { _ in }
checkBool(openMode.1.allowCount == 1, true, "open-lid shutdown releases assertions")
checkBool(openMode.2.allowCount == 0, true, "open-lid shutdown leaves clamshell sleep alone")

let primaryClosedMode = makeWakeController()
primaryClosedMode.0.apply(.lidClosed) { _ in }
checkWakeMode(primaryClosedMode.0.mode, .lidClosed, "primary clamshell activation updates mode")
checkBool(primaryClosedMode.1.preventCount == 1, true, "lid-closed activation starts assertions")
checkBool(primaryClosedMode.1.isKeepingDisplayAwake, true,
          "lid-closed mode keeps displays awake by default")
checkBool(primaryClosedMode.2.preventCount == 1, true, "lid-closed activation applies selector")
checkBool(primaryClosedMode.3.calls.isEmpty, true, "working selector skips fallback")
primaryClosedMode.0.apply(.off) { _ in }
checkWakeMode(primaryClosedMode.0.mode, .off, "turning off clears primary clamshell mode")
checkBool(primaryClosedMode.1.allowCount == 1, true, "turning off releases assertions")
checkBool(primaryClosedMode.2.allowCount == 1, true, "turning off restores clamshell sleep")

let failedRestoreClamshell = FakeClamshellSleep()
let failedRestoreMode = makeWakeController(clamshell: failedRestoreClamshell)
failedRestoreMode.0.apply(.lidClosed) { _ in }
failedRestoreClamshell.allowResult = .failure(TestWakeError.failed)
var restoreFailureReported = false
failedRestoreMode.0.apply(.off) { result in
    if case .failure = result { restoreFailureReported = true }
}
checkBool(restoreFailureReported, true, "failed clamshell restore is reported")
checkWakeMode(failedRestoreMode.0.mode, .lidClosed, "failed clamshell restore stays active")
checkBool(failedRestoreMode.1.allowCount == 0, true, "failed clamshell restore keeps assertions")

let fallbackClamshell = FakeClamshellSleep()
fallbackClamshell.preventResult = .failure(TestWakeError.failed)
let fallbackClosedMode = makeWakeController(clamshell: fallbackClamshell)
fallbackClosedMode.0.apply(.lidClosed) { _ in }
checkWakeMode(fallbackClosedMode.0.mode, .lidClosed, "fallback can activate lid-closed mode")
checkBool(fallbackClosedMode.3.calls == [true], true, "selector failure enables fallback")
fallbackClosedMode.0.apply(.off) { _ in }
checkBool(fallbackClosedMode.3.calls == [true, false], true, "turning off disables fallback")
checkBool(fallbackClosedMode.1.allowCount == 1, true, "fallback shutdown releases assertions")
checkBool(fallbackClosedMode.2.allowCount == 1, true, "fallback shutdown does not retry selector restore")

let fallbackUpgradeClamshell = FakeClamshellSleep()
fallbackUpgradeClamshell.preventResult = .failure(TestWakeError.failed)
let fallbackUpgradeMode = makeWakeController(clamshell: fallbackUpgradeClamshell)
fallbackUpgradeMode.0.apply(.lidClosed) { _ in }
fallbackUpgradeMode.0.apply(.openLid) { _ in }
checkWakeMode(fallbackUpgradeMode.0.mode, .openLid, "fallback can downgrade to open-lid mode")
checkBool(fallbackUpgradeMode.3.calls == [true, false], true, "open-lid downgrade disables fallback")
checkBool(fallbackUpgradeMode.2.allowCount == 1, true, "open-lid downgrade does not retry selector restore")

let failedAssertions = FakeWakeAssertions()
failedAssertions.preventResult = .failure(TestWakeError.failed)
let failedOpenMode = makeWakeController(assertions: failedAssertions)
var openFailureReported = false
failedOpenMode.0.apply(.openLid) { result in
    if case .failure = result { openFailureReported = true }
}
checkBool(openFailureReported, true, "assertion activation failure is reported")
checkWakeMode(failedOpenMode.0.mode, .off, "failed open-lid activation stays off")

let failedClamshell = FakeClamshellSleep()
failedClamshell.preventResult = .failure(TestWakeError.failed)
let failedFallback = FakeSleepFallback()
failedFallback.enableResult = .failure(TestWakeError.failed)
let failedClosedMode = makeWakeController(
    clamshell: failedClamshell,
    fallback: failedFallback
)
var closedFailureReported = false
failedClosedMode.0.apply(.lidClosed) { result in
    if case .failure = result { closedFailureReported = true }
}
checkBool(closedFailureReported, true, "clamshell activation failure is reported")
checkWakeMode(failedClosedMode.0.mode, .off, "failed lid-closed activation stays off")
checkBool(failedClosedMode.1.allowCount == 1, true, "failed lid-closed activation rolls back assertions")
checkBool(failedClosedMode.2.allowCount == 1, true, "failed lid-closed activation restores selector")

let displaySleepOpenMode = makeWakeController(shouldKeepDisplayAwake: false)
displaySleepOpenMode.0.apply(.openLid) { _ in }
checkBool(displaySleepOpenMode.1.isPreventingSystemIdleSleep, true,
          "open-lid display sleep keeps system idle assertion")
checkBool(displaySleepOpenMode.1.isKeepingDisplayAwake, false,
          "open-lid display sleep omits display assertion")

let displaySleepClosedMode = makeWakeController(shouldKeepDisplayAwake: false)
displaySleepClosedMode.0.apply(.lidClosed) { _ in }
checkBool(displaySleepClosedMode.1.isPreventingSystemIdleSleep, true,
          "lid-closed display sleep keeps system idle assertion")
checkBool(displaySleepClosedMode.1.isKeepingDisplayAwake, false,
          "lid-closed display sleep omits display assertion")
checkBool(displaySleepClosedMode.2.preventCount == 1, true,
          "lid-closed display sleep keeps clamshell override")

var liveDisplayUpdateSucceeded = false
displaySleepClosedMode.0.setShouldKeepDisplayAwake(true) { result in
    if case .success = result { liveDisplayUpdateSucceeded = true }
}
checkBool(liveDisplayUpdateSucceeded, true,
          "active display policy update succeeds")
checkBool(displaySleepClosedMode.0.shouldKeepDisplayAwake, true,
          "active display policy update records preference")
checkBool(displaySleepClosedMode.1.isKeepingDisplayAwake, true,
          "active display policy update starts display assertion")
checkWakeMode(displaySleepClosedMode.0.mode, .lidClosed,
              "active display policy update preserves wake mode")
checkBool(displaySleepClosedMode.2.preventCount == 1, true,
          "active display policy update does not repeat clamshell override")

var liveDisplaySleepUpdateSucceeded = false
displaySleepClosedMode.0.setShouldKeepDisplayAwake(false) { result in
    if case .success = result { liveDisplaySleepUpdateSucceeded = true }
}
checkBool(liveDisplaySleepUpdateSucceeded, true,
          "active display sleep update succeeds")
checkBool(displaySleepClosedMode.1.isPreventingSystemIdleSleep, true,
          "active display sleep update keeps system idle assertion")
checkBool(displaySleepClosedMode.1.isKeepingDisplayAwake, false,
          "active display sleep update releases display assertion")
checkWakeMode(displaySleepClosedMode.0.mode, .lidClosed,
              "active display sleep update preserves wake mode")
checkBool(displaySleepClosedMode.2.preventCount == 1, true,
          "active display sleep update does not repeat clamshell override")

let inactiveDisplayPolicyMode = makeWakeController()
inactiveDisplayPolicyMode.0.setShouldKeepDisplayAwake(false) { _ in }
inactiveDisplayPolicyMode.0.apply(.openLid) { _ in }
checkBool(inactiveDisplayPolicyMode.1.isPreventingSystemIdleSleep, true,
          "inactive display policy keeps next mode awake")
checkBool(inactiveDisplayPolicyMode.1.isKeepingDisplayAwake, false,
          "inactive display policy applies to next mode")

let failedDisplayUpdateAssertions = FakeWakeAssertions()
let failedDisplayUpdateMode = makeWakeController(
    assertions: failedDisplayUpdateAssertions,
    shouldKeepDisplayAwake: false
)
failedDisplayUpdateMode.0.apply(.openLid) { _ in }
failedDisplayUpdateAssertions.updateDisplayResult = .failure(TestWakeError.failed)
var displayUpdateFailureReported = false
failedDisplayUpdateMode.0.setShouldKeepDisplayAwake(true) { result in
    if case .failure = result { displayUpdateFailureReported = true }
}
checkBool(displayUpdateFailureReported, true,
          "failed display policy update is reported")
checkBool(failedDisplayUpdateMode.0.shouldKeepDisplayAwake, false,
          "failed display policy update retains previous preference")
checkWakeMode(failedDisplayUpdateMode.0.mode, .openLid,
              "failed display policy update preserves wake mode")

if failures > 0 {
    print("\(failures) failing")
    exit(1)
} else {
    print("all passing")
    exit(0)
}
