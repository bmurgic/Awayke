//
//  AppDelegate.swift
//  Awayke
//

import AppKit
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let powerManager = PowerManager()
    private let helper = HelperManager.shared
    private let displayKeeper = DisplayWakeKeeper()
    private let keepDisplaysAwakePreference = KeepDisplaysAwakePreference()
    private let clamshellKeeper = ClamshellWakeKeeper()
    private let batteryMonitor = BatteryMonitor()
    private let autoOffTimer = AutoOffTimer()
    private let lidMonitor = LidMonitor()
    private let lidSession = LidSessionTracker()
    private var statusInteractionView: StatusItemInteractionView?

    private lazy var wakeModeController = WakeModeController(
        assertions: displayKeeper,
        clamshell: clamshellKeeper,
        fallback: powerManager,
        shouldKeepDisplayAwake: keepDisplaysAwakePreference.value
    )
    private lazy var statusInteractionController = StatusItemInteractionController(
        onAction: { [weak self] action in
            self?.handleStatusClick(action)
        },
        onContextMenu: { [weak self] in
            self?.showMenu()
        }
    )
    private let thresholdDefaultsKey = "autoOffThreshold"
    private let thresholdOptions = [0, 10, 20, 30]
    private let durationOptions = [15, 30, 60, 120]

    /// The user's requested mode, retained while battery auto-off is active.
    private var intentMode = WakeMode.off
    /// Battery auto-off is currently holding Awayke off.
    private var suspendedForBattery = false
    /// The user turned Awayke on while already below the floor. Auto-off
    /// stands down until the machine next reaches AC.
    private var overrideBattery = false
    /// Most recent battery reading, for re-evaluating on threshold change.
    private var lastSnapshot: BatterySnapshot?
    /// A wake-mode transition is outstanding. Guards against overlapping
    /// operations and duplicate admin prompts on the fallback path.
    private var powerChangeInFlight = false
    /// A session can end while a battery-driven pmset change is still in
    /// flight. Remember that event so it is not lost.
    private var pendingSessionEnd: SessionEndReason?

    private enum SessionEndReason {
        case timer
        case lidReopened

        var notificationBody: String {
            switch self {
            case .timer: return "Timer finished."
            case .lidReopened: return "The lid was reopened."
            }
        }
    }

    /// Low-battery floor; 0 disables the feature. Persisted.
    private var threshold: Int {
        get { UserDefaults.standard.integer(forKey: thresholdDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: thresholdDefaultsKey) }
    }

    /// What is actually applied to the system.
    private var effectiveMode: WakeMode { wakeModeController.mode }
    private var effectiveActive: Bool { effectiveMode.isActive }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        helper.register()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleAccessibleActivation(_:))

            let interactionView = StatusItemInteractionView(
                frame: button.bounds,
                controller: statusInteractionController
            )
            interactionView.autoresizingMask = [.width, .height]
            button.addSubview(interactionView)
            statusInteractionView = interactionView
        }

        refreshStatusItem()

        // Recovery from crash / force-kill: pmset disablesleep is a
        // persistent system setting, so a previous instance that died
        // without running its quit cleanup leaves SleepDisabled = 1.
        // Silently reset it via the helper. Skipped if the helper isn't
        // approved (no password prompt for cleanup the user didn't ask for).
        if helper.isUsable {
            powerManager.disableSleep(false) { _ in }
        }

        if threshold > 0 {
            requestNotificationAuthorization()
        }

        batteryMonitor.onChange = { [weak self] snapshot in
            self?.handleBattery(snapshot)
        }
        batteryMonitor.start()

        autoOffTimer.onExpire = { [weak self] in self?.handleTimerExpired() }
        // Keeps the tooltip's remaining-time readout live.
        autoOffTimer.onTick = { [weak self] in self?.refreshStatusItem() }

        lidMonitor.onChange = { [weak self] closed in
            guard let self else { return }
            if self.lidSession.handle(lidClosed: closed) {
                self.endSession(reason: .lidReopened)
            }
        }
        lidMonitor.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Never leave a wake override active. Defer termination until a
        // fallback pmset cleanup finishes, so the main run loop stays alive
        // for any authentication UI the fallback may need to show.
        guard effectiveActive else { return .terminateNow }

        wakeModeController.apply(.off) { _ in
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    @objc private func handleAccessibleActivation(_ sender: NSStatusBarButton) {
        statusInteractionController.receiveAccessibleActivation()
    }

    private func handleStatusClick(_ action: StatusClickAction) {
        setMode(effectiveMode.target(after: action))
    }

    // MARK: - State application

    /// Applies a user-requested mode. Always clears any battery suspension,
    /// because an explicit activation overrides the auto-off machine.
    ///
    /// - Parameters:
    ///   - timerMinutes: Arms the auto-off countdown for this many minutes.
    ///   - untilLidReopens: Ends after a lid close/open cycle.
    ///
    /// With neither session option, an active mode is indefinite.
    private func setMode(_ mode: WakeMode,
                         timerMinutes: Int? = nil,
                         untilLidReopens: Bool = false) {
        guard !powerChangeInFlight else { return }
        powerChangeInFlight = true

        wakeModeController.apply(mode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.powerChangeInFlight = false
                switch result {
                case .success:
                    self.intentMode = mode
                    self.suspendedForBattery = false
                    // Only an "on" issued while already below the floor
                    // counts as an override. Turning on at a healthy
                    // charge leaves auto-off armed for the discharge.
                    self.overrideBattery = mode.isActive && self.isBelowFloor
                    if mode.isActive, untilLidReopens {
                        self.autoOffTimer.cancel()
                        self.lidSession.start(lidClosed: self.lidMonitor.isClosed)
                    } else if mode.isActive, let minutes = timerMinutes {
                        self.lidSession.cancel()
                        self.autoOffTimer.start(minutes: minutes)
                    } else {
                        self.autoOffTimer.cancel()
                        self.lidSession.cancel()
                    }
                    self.refreshStatusItem()
                case .failure(let error):
                    self.presentError(error)
                }
                self.processPendingSessionEnd()
            }
        }
    }

    /// Latest reading is on battery and under the configured floor.
    private var isBelowFloor: Bool {
        guard threshold > 0, let snapshot = lastSnapshot else { return false }
        return !snapshot.onAC && snapshot.percent < threshold
    }

    /// The countdown ran out. Same end state as a manual "Turn Off".
    private func handleTimerExpired() {
        endSession(reason: .timer)
    }

    /// Ends either kind of bounded session. This is intentionally shared by
    /// timer and lid sessions so both interact identically with battery
    /// suspension and in-flight helper calls.
    private func endSession(reason: SessionEndReason) {
        autoOffTimer.cancel()
        lidSession.cancel()
        guard intentMode.isActive else { return }

        // Battery auto-off already re-enabled sleep, so there is nothing
        // to undo at the system level - just clear the state. Avoids a
        // redundant pmset round-trip (and an admin prompt on the
        // osascript fallback path).
        guard !suspendedForBattery else {
            intentMode = .off
            suspendedForBattery = false
            overrideBattery = false
            refreshStatusItem()
            notify(title: "Awayke turned off", body: reason.notificationBody)
            return
        }

        guard !powerChangeInFlight else {
            pendingSessionEnd = reason
            return
        }
        powerChangeInFlight = true

        wakeModeController.apply(.off) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.powerChangeInFlight = false
                switch result {
                case .success:
                    self.intentMode = .off
                    self.overrideBattery = false
                    self.refreshStatusItem()
                    self.notify(title: "Awayke turned off", body: reason.notificationBody)
                case .failure(let error):
                    // Do not claim the session ended if the active wake
                    // mechanism could not be restored. The icon remains
                    // active and the error makes the failed safety action
                    // visible to the user.
                    //
                    // LidSessionTracker.handle already cleared itself when it
                    // reported the reopen, so without this the session is gone
                    // and nothing can ever end it. Re-arm so the next
                    // close/open cycle retries. A timer deadline has genuinely
                    // passed and has no duration to restore, so it does not
                    // re-arm.
                    if case .lidReopened = reason {
                        self.lidSession.start(lidClosed: self.lidMonitor.isClosed)
                    }
                    self.refreshStatusItem()
                    self.presentError(error)
                }
            }
        }
    }

    private func processPendingSessionEnd() {
        guard !powerChangeInFlight, let reason = pendingSessionEnd else { return }
        pendingSessionEnd = nil
        endSession(reason: reason)
    }

    private func handleBattery(_ snapshot: BatterySnapshot) {
        lastSnapshot = snapshot
        overrideBattery = AutoOffPolicy.shouldKeepOverride(overrideBattery, onAC: snapshot.onAC)

        let action = AutoOffPolicy.decide(
            intent: intentMode.isActive,
            suspended: suspendedForBattery,
            overridden: overrideBattery,
            percent: snapshot.percent,
            onAC: snapshot.onAC,
            threshold: threshold
        )
        guard action != .none else { return }

        // Power notifications arrive faster than a wake-mode transition
        // completes. Drop this one - the in-flight completion
        // re-evaluates against the newest reading.
        guard !powerChangeInFlight else { return }
        powerChangeInFlight = true

        let suspending = (action == .suspend)
        let targetMode = suspending ? WakeMode.off : intentMode
        wakeModeController.apply(targetMode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.powerChangeInFlight = false
                guard case .success = result else {
                    self.processPendingSessionEnd()
                    return
                }

                self.suspendedForBattery = suspending
                self.refreshStatusItem()
                if suspending {
                    self.notify(title: "Awayke turned off",
                                body: "Battery dropped below \(self.threshold)%.")
                } else {
                    self.notify(title: "Awayke back on",
                                body: "Charging - sleep prevention resumed.")
                }

                self.processPendingSessionEnd()

                // State moved on; re-check against anything that arrived
                // while we were waiting. Terminates because each pass
                // flips `suspendedForBattery`.
                if let latest = self.lastSnapshot {
                    self.handleBattery(latest)
                }
            }
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()

        let stateTitle: String
        if suspendedForBattery {
            stateTitle = "Paused (low battery)"
        } else if effectiveActive, lidSession.isActive {
            stateTitle = lidSession.isWaitingForClose
                ? "Lid-closed mode - waiting for lid to close"
                : "Lid-closed mode - until lid reopens"
        } else if effectiveActive, let remaining = autoOffTimer.remaining {
            stateTitle = "Lid-closed mode - \(formatRemaining(remaining)) left"
        } else {
            switch effectiveMode {
            case .off:
                stateTitle = "Off"
            case .openLid:
                stateTitle = "Open-lid mode"
            case .lidClosed:
                stateTitle = "Lid-closed mode"
            }
        }
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(.separator())

        menu.addItem(keepAwakeSubmenuItem())
        menu.addItem(keepDisplaysAwakeMenuItem())
        menu.addItem(autoOffSubmenuItem())

        if let helperRow = helperStatusMenuItem() {
            menu.addItem(.separator())
            menu.addItem(helperRow)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Uninstall Awayke…", action: #selector(menuUninstall), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Awayke", action: #selector(menuQuit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func keepAwakeSubmenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Keep awayke for", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let lidSessionItem = NSMenuItem(
            title: "Until lid is reopened",
            action: #selector(menuKeepAwakeUntilLidReopens),
            keyEquivalent: ""
        )
        lidSessionItem.target = self
        lidSessionItem.state = (effectiveActive && lidSession.isActive) ? .on : .off
        submenu.addItem(lidSessionItem)

        submenu.addItem(.separator())

        for value in durationOptions {
            let item = NSMenuItem(title: durationLabel(value),
                                  action: #selector(menuKeepAwakeFor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        // Tag 0 means "no countdown" - on until turned off.
        let indefinite = NSMenuItem(title: "Indefinitely",
                                    action: #selector(menuKeepAwakeFor(_:)), keyEquivalent: "")
        indefinite.target = self
        indefinite.tag = 0
        indefinite.state = (effectiveActive && !autoOffTimer.isRunning && !lidSession.isActive) ? .on : .off
        submenu.addItem(indefinite)

        parent.submenu = submenu
        return parent
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourPart = hours == 1 ? "1 hour" : "\(hours) hours"
        return rest == 0 ? hourPart : "\(hourPart) \(rest) min"
    }

    /// Rounded up to the next whole minute, so a live countdown never
    /// reads "0m" while Awayke is still on.
    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private func keepDisplaysAwakeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Keep displays awake",
            action: #selector(menuToggleKeepDisplaysAwake),
            keyEquivalent: ""
        )
        item.target = self
        item.offStateImage = NSImage(size: item.onStateImage.size)
        item.state = keepDisplaysAwakePreference.value ? .on : .off
        return item
    }

    private func autoOffSubmenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Auto-off on low battery", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = threshold
        for value in thresholdOptions {
            let label = value == 0 ? "Off" : "At \(value)%"
            let item = NSMenuItem(title: label, action: #selector(menuSetThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = (value == current) ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func helperStatusMenuItem() -> NSMenuItem? {
        switch helper.state {
        case .enabled:
            return nil
        case .awaitingApproval:
            return NSMenuItem(title: "Approve helper in System Settings…", action: #selector(menuApproveHelper), keyEquivalent: "")
        case .notRegistered:
            let item = NSMenuItem(title: "Installing helper…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .notFound:
            let item = NSMenuItem(title: "Helper not found (using fallback)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
    }

    @objc private func menuKeepAwakeFor(_ sender: NSMenuItem) {
        let minutes = sender.tag
        if minutes > 0 {
            requestNotificationAuthorization()
        }
        setMode(.lidClosed, timerMinutes: minutes > 0 ? minutes : nil)
    }

    @objc private func menuKeepAwakeUntilLidReopens() {
        requestNotificationAuthorization()
        setMode(.lidClosed, untilLidReopens: true)
    }

    @objc private func menuToggleKeepDisplaysAwake() {
        guard !powerChangeInFlight else { return }

        let shouldKeepDisplayAwake = !keepDisplaysAwakePreference.value
        wakeModeController.setShouldKeepDisplayAwake(
            shouldKeepDisplayAwake
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.keepDisplaysAwakePreference.value = shouldKeepDisplayAwake
            case .failure(let error):
                self.presentError(error)
            }
        }
    }

    @objc private func menuSetThreshold(_ sender: NSMenuItem) {
        threshold = sender.tag
        if threshold > 0 {
            requestNotificationAuthorization()
        }
        // Re-evaluate against the latest reading so a newly-set threshold
        // that is already breached suspends immediately.
        if let snapshot = lastSnapshot {
            handleBattery(snapshot)
        }
    }

    @objc private func menuApproveHelper() { helper.revealInSystemSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Awayke?"
        alert.informativeText = "This will remove Awayke's background helper from System Settings and quit the app. You can then move Awayke.app to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        helper.unregister()
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Status item rendering

    private func refreshStatusItem() {
        guard let statusItem, let button = statusItem.button else { return }
        let image = StatusIconRenderer.image(for: effectiveMode)
        statusItem.length = image.size.width
        button.image = image
        button.contentTintColor = nil
        button.title = ""
        if suspendedForBattery {
            button.toolTip = "Awayke paused - battery below \(threshold)%. Plug in to resume."
        } else if effectiveMode == .lidClosed, lidSession.isActive {
            button.toolTip = lidSession.isWaitingForClose
                ? "Awayke Lid-closed mode is on - it will turn off after the lid is closed and reopened."
                : "Awayke Lid-closed mode is on - it will turn off when the lid is reopened."
        } else if effectiveMode == .lidClosed, let remaining = autoOffTimer.remaining {
            button.toolTip = "Awayke Lid-closed mode is on - turning off in \(formatRemaining(remaining))."
        } else {
            switch effectiveMode {
            case .off:
                button.toolTip = "Awayke is off. Single-click for Open-lid mode; double-click for Lid-closed mode."
            case .openLid:
                button.toolTip = "Awayke Open-lid mode is on. Single-click to turn off; double-click for Lid-closed mode."
            case .lidClosed:
                button.toolTip = "Awayke Lid-closed mode is on. Single-click or double-click to turn off."
            }
        }
        statusInteractionView?.toolTip = button.toolTip
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Awayke couldn't toggle sleep."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
