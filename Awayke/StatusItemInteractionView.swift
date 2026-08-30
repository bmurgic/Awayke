import AppKit

final class StatusItemInteractionView: NSView {
    private let controller: StatusItemInteractionController

    init(frame frameRect: NSRect,
         controller: StatusItemInteractionController) {
        self.controller = controller
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        statusButton?.highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        statusButton?.highlight(false)
        guard contains(event) else { return }
        controller.receiveLeftClick(count: event.clickCount)
    }

    override func rightMouseDown(with event: NSEvent) {
        statusButton?.highlight(true)
    }

    override func rightMouseUp(with event: NSEvent) {
        statusButton?.highlight(false)
        guard contains(event) else { return }
        controller.receiveRightClick()
    }

    private var statusButton: NSButton? {
        superview as? NSButton
    }

    private func contains(_ event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location)
    }
}
