import AppKit

enum StatusIconRenderer {
    private static let iconSize = NSSize(width: 16, height: 14)
    private static let screenRect = NSRect(x: 1.5, y: 4, width: 13, height: 9)
    private static let baseRect = NSRect(x: 0.5, y: 0.5, width: 15, height: 2)
    private static let screenCornerRadius: CGFloat = 2
    private static let outlineWidth: CGFloat = 1.5

    private static let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private static let subtleGray = NSColor(
        srgbRed: 184 / 255,
        green: 186 / 255,
        blue: 196 / 255,
        alpha: 1
    )
    private static let screenPurple = NSColor(
        srgbRed: 203 / 255,
        green: 166 / 255,
        blue: 247 / 255,
        alpha: 1
    )
    private static let basePurple = NSColor(
        srgbRed: 152 / 255,
        green: 123 / 255,
        blue: 194 / 255,
        alpha: 1
    )

    static func image(for mode: WakeMode) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true

            let filledScreenPath = NSBezierPath(
                roundedRect: screenRect,
                xRadius: screenCornerRadius,
                yRadius: screenCornerRadius
            )
            let outlineInset = outlineWidth / 2
            let outlinedScreenPath = NSBezierPath(
                roundedRect: screenRect.insetBy(dx: outlineInset, dy: outlineInset),
                xRadius: screenCornerRadius - outlineInset,
                yRadius: screenCornerRadius - outlineInset
            )
            let basePath = NSBezierPath(
                roundedRect: baseRect,
                xRadius: baseRect.height / 2,
                yRadius: baseRect.height / 2
            )

            switch mode {
            case .off:
                white.setStroke()
                outlinedScreenPath.lineWidth = outlineWidth
                outlinedScreenPath.stroke()
                subtleGray.setFill()
                basePath.fill()
            case .openLid:
                white.setFill()
                filledScreenPath.fill()
                subtleGray.setFill()
                basePath.fill()
            case .lidClosed:
                screenPurple.setFill()
                filledScreenPath.fill()
                basePurple.setFill()
                basePath.fill()
            }

            return true
        }
        image.isTemplate = false
        image.size = iconSize
        return image
    }
}
