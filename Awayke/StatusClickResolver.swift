import AppKit

nonisolated final class ScheduledClick {
    private let onCancel: () -> Void
    private(set) var isCancelled = false

    init(onCancel: @escaping () -> Void = {}) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

nonisolated final class StatusClickResolver {
    private static let fallbackDoubleClickInterval: TimeInterval = 0.5

    typealias Schedule = (
        _ delay: TimeInterval,
        _ action: @escaping () -> Void
    ) -> ScheduledClick

    private let doubleClickInterval: TimeInterval
    private let schedule: Schedule
    private var pendingSingleClick: ScheduledClick?

    convenience init() {
        self.init(
            systemDoubleClickInterval: NSEvent.doubleClickInterval,
            schedule: Self.scheduleOnMainQueue
        )
    }

    init(systemDoubleClickInterval: TimeInterval,
         schedule: @escaping Schedule) {
        doubleClickInterval = systemDoubleClickInterval > 0
            ? systemDoubleClickInterval
            : Self.fallbackDoubleClickInterval
        self.schedule = schedule
    }

    func receive(clickCount: Int,
                 resolve: @escaping (StatusClickAction) -> Void) {
        guard (1...2).contains(clickCount) else { return }

        if pendingSingleClick != nil {
            cancel()
            resolve(.doubleClick)
            return
        }

        switch clickCount {
        case 1:
            pendingSingleClick = schedule(doubleClickInterval) { [weak self] in
                guard let self else { return }
                self.pendingSingleClick = nil
                resolve(.singleClick)
            }
        case 2:
            resolve(.doubleClick)
        default:
            break
        }
    }

    func cancel() {
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
    }

    deinit {
        cancel()
    }

    private nonisolated static func scheduleOnMainQueue(
        after delay: TimeInterval,
        action: @escaping () -> Void
    ) -> ScheduledClick {
        let scheduledClick = ScheduledClick()
        let workItem = DispatchWorkItem {
            guard !scheduledClick.isCancelled else { return }
            action()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return scheduledClick
    }
}

nonisolated final class StatusItemInteractionController {
    private let resolver: StatusClickResolver
    private let onAction: (StatusClickAction) -> Void
    private let onContextMenu: () -> Void

    init(resolver: StatusClickResolver = StatusClickResolver(),
         onAction: @escaping (StatusClickAction) -> Void,
         onContextMenu: @escaping () -> Void) {
        self.resolver = resolver
        self.onAction = onAction
        self.onContextMenu = onContextMenu
    }

    func receiveLeftClick(count: Int) {
        resolver.receive(clickCount: count, resolve: onAction)
    }

    func receiveRightClick() {
        resolver.cancel()
        onContextMenu()
    }

    func receiveAccessibleActivation() {
        resolver.cancel()
        onAction(.singleClick)
    }
}
