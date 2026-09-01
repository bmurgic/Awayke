import AppKit

enum StatusIconRenderer {
    private static let svgViewportSize: CGFloat = 24
    private static let iconSideLength: CGFloat = 18
    private static let iconSize = NSSize(
        width: iconSideLength,
        height: iconSideLength
    )
    private static let svgScale = iconSideLength / svgViewportSize
    private static let strokeWidth: CGFloat = 1.5 * svgScale

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

            let screenPath = makeScreenPath()
            let basePath = makeBasePath()

            switch mode {
            case .off:
                drawStroke(screenPath, color: white)
                drawFillAndStroke(basePath, color: subtleGray)
            case .openLid:
                drawFillAndStroke(screenPath, color: white)
                drawFillAndStroke(basePath, color: subtleGray)
            case .lidClosed:
                drawFillAndStroke(screenPath, color: screenPurple)
                drawFillAndStroke(basePath, color: basePurple)
            }

            return true
        }
        image.isTemplate = false
        image.size = iconSize
        return image
    }

    private static func drawStroke(_ path: NSBezierPath, color: NSColor) {
        color.setStroke()
        path.stroke()
    }

    private static func drawFillAndStroke(_ path: NSBezierPath, color: NSColor) {
        color.setFill()
        path.fill()
        color.setStroke()
        path.stroke()
    }

    private static func makeScreenPath() -> NSBezierPath {
        let path = NSBezierPath()

        path.move(to: point(x: 3.49609, y: 17))
        path.line(to: point(x: 3.49609, y: 10))
        path.curve(
            to: point(x: 4.37477, y: 4.87868),
            controlPoint1: point(x: 3.49609, y: 7.17157),
            controlPoint2: point(x: 3.49609, y: 5.75736)
        )
        path.curve(
            to: point(x: 9.49609, y: 4),
            controlPoint1: point(x: 5.25345, y: 4),
            controlPoint2: point(x: 6.66767, y: 4)
        )
        path.line(to: point(x: 14.4961, y: 4))
        path.curve(
            to: point(x: 19.6174, y: 4.87868),
            controlPoint1: point(x: 17.3245, y: 4),
            controlPoint2: point(x: 18.7387, y: 4)
        )
        path.curve(
            to: point(x: 20.4961, y: 10),
            controlPoint1: point(x: 20.4961, y: 5.75736),
            controlPoint2: point(x: 20.4961, y: 7.17157)
        )
        path.line(to: point(x: 20.4961, y: 17))
        path.line(to: point(x: 15.4961, y: 17))
        path.line(to: point(x: 15.4961, y: 17.9))
        path.line(to: point(x: 8.49609, y: 17.9))
        path.line(to: point(x: 8.49609, y: 17))
        path.close()

        return makeBezierPath(from: path, lineCapStyle: .round)
    }

    private static func makeBasePath() -> NSBezierPath {
        let path = NSBezierPath()

        path.move(to: point(x: 2.81428, y: 17))
        path.line(to: point(x: 8.49609, y: 17))
        path.line(to: point(x: 8.49609, y: 17.9))
        path.line(to: point(x: 15.4961, y: 17.9))
        path.line(to: point(x: 15.4961, y: 17))
        path.line(to: point(x: 21.1779, y: 17))
        path.curve(
            to: point(x: 21.9961, y: 17.8182),
            controlPoint1: point(x: 21.6314, y: 17),
            controlPoint2: point(x: 21.9961, y: 17.3647)
        )
        path.curve(
            to: point(x: 19.8143, y: 20),
            controlPoint1: point(x: 21.9961, y: 19.0231),
            controlPoint2: point(x: 21.0192, y: 20)
        )
        path.line(to: point(x: 4.17791, y: 20))
        path.curve(
            to: point(x: 1.99609, y: 17.8182),
            controlPoint1: point(x: 2.97297, y: 20),
            controlPoint2: point(x: 1.99609, y: 19.0231)
        )
        path.curve(
            to: point(x: 2.81428, y: 17),
            controlPoint1: point(x: 1.99609, y: 17.3647),
            controlPoint2: point(x: 2.36079, y: 17)
        )
        path.close()

        return makeBezierPath(from: path, lineCapStyle: .butt)
    }

    private static func makeBezierPath(
        from path: NSBezierPath,
        lineCapStyle: NSBezierPath.LineCapStyle
    ) -> NSBezierPath {
        path.lineWidth = strokeWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = lineCapStyle
        return path
    }

    private static func point(x: CGFloat, y: CGFloat) -> NSPoint {
        NSPoint(
            x: x * svgScale,
            y: iconSideLength - y * svgScale
        )
    }
}
