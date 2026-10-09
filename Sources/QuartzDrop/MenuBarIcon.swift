import AppKit

/// The menu bar version of the app icon: the drop outline with its terminal prompt, drawn as a
/// template image so macOS tints it for light, dark, and highlighted menu bars.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            // Drawn in the 44 x 56 coordinates of the compact mark, scaled to 16 pt tall.
            let scale = (rect.height - 2) / 56
            var transform = AffineTransform(scale: scale)
            transform.append(AffineTransform(translationByX: (rect.width - 44 * scale) / 2, byY: 1))
            func stroke(_ path: NSBezierPath, width: CGFloat) {
                path.transform(using: transform)
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            NSColor.black.setStroke()

            let drop = NSBezierPath()
            drop.move(to: NSPoint(x: 22, y: 2))
            drop.curve(
                to: NSPoint(x: 6, y: 26), controlPoint1: NSPoint(x: 15, y: 12),
                controlPoint2: NSPoint(x: 9, y: 18))
            drop.curve(
                to: NSPoint(x: 22, y: 52), controlPoint1: NSPoint(x: 1, y: 38),
                controlPoint2: NSPoint(x: 8, y: 52))
            drop.curve(
                to: NSPoint(x: 38, y: 26), controlPoint1: NSPoint(x: 36, y: 52),
                controlPoint2: NSPoint(x: 43, y: 38))
            drop.curve(
                to: NSPoint(x: 22, y: 2), controlPoint1: NSPoint(x: 35, y: 18),
                controlPoint2: NSPoint(x: 29, y: 12))
            drop.close()
            stroke(drop, width: 1.4)

            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: 9, y: 22))
            divider.line(to: NSPoint(x: 35, y: 22))
            stroke(divider, width: 1)

            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: 14, y: 28))
            prompt.line(to: NSPoint(x: 20, y: 33))
            prompt.line(to: NSPoint(x: 14, y: 38))
            stroke(prompt, width: 1.5)

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 24, y: 39))
            cursor.line(to: NSPoint(x: 31, y: 39))
            stroke(cursor, width: 1.5)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "quartz-drop"
        return image
    }
}
