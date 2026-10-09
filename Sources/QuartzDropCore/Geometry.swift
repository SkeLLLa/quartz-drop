/// Integer rectangle in global screen coordinates with the origin at the top-left corner of the
/// primary display and y growing downwards (the Accessibility API convention).
public struct Rect: Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public func contains(_ point: Point) -> Bool {
        point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
    }

    public func overlapArea(with other: Rect) -> Int {
        let left = max(x, other.x)
        let top = max(y, other.y)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return 0 }
        return (right - left) * (bottom - top)
    }

    public var description: String { "\(width)x\(height) at \(x),\(y)" }
}

public struct Point: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct ScreenInfo: Hashable, Sendable {
    /// Display name as shown by macOS, e.g. `Built-in Retina Display` or `DELL U2720Q`.
    public var name: String
    /// Full display bounds.
    public var frame: Rect
    /// Display bounds without the menu bar and Dock; placement is resolved against this area.
    public var visibleFrame: Rect

    public init(name: String, frame: Rect, visibleFrame: Rect) {
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    public func placementRect(_ placement: PlacementConfig) -> Rect {
        let area = visibleFrame
        let width = Self.resolve(placement.width, axis: area.width)
        let height = Self.resolve(placement.height, axis: area.height)

        let baseX: Int
        switch placement.position {
        case .topLeft, .left, .bottomLeft: baseX = area.x
        case .top, .center, .bottom: baseX = area.x + (area.width - width) / 2
        case .topRight, .right, .bottomRight: baseX = area.maxX - width
        }

        let baseY: Int
        switch placement.position {
        case .topLeft, .top, .topRight: baseY = area.y
        case .left, .center, .right: baseY = area.y + (area.height - height) / 2
        case .bottomLeft, .bottom, .bottomRight: baseY = area.maxY - height
        }

        let offsetX = Self.resolve(placement.offsetX, axis: area.width)
        let offsetY = Self.resolve(placement.offsetY, axis: area.height)

        let (x, finalWidth) = Self.placeAxis(
            start: area.x, length: area.width, size: width, base: baseX, offset: offsetX)
        let (y, finalHeight) = Self.placeAxis(
            start: area.y, length: area.height, size: height, base: baseY, offset: offsetY)
        return Rect(x: x, y: y, width: finalWidth, height: finalHeight)
    }

    public func validatePlacement(_ placement: PlacementConfig) throws {
        let width = Self.resolve(placement.width, axis: visibleFrame.width)
        let height = Self.resolve(placement.height, axis: visibleFrame.height)
        if width < 1 {
            throw ConfigError("placement width resolved to \(width), must be at least 1")
        }
        if height < 1 {
            throw ConfigError("placement height resolved to \(height), must be at least 1")
        }
        if width > visibleFrame.width {
            throw ConfigError(
                "placement width resolved to \(width), exceeds screen width \(visibleFrame.width)")
        }
        if height > visibleFrame.height {
            throw ConfigError(
                "placement height resolved to \(height), exceeds screen height \(visibleFrame.height)"
            )
        }
    }

    public static func resolve(_ metric: PlacementMetric, axis: Int) -> Int {
        switch metric {
        case .percent(let percent): axis * percent / 100
        case .pixels(let pixels): pixels
        }
    }

    private static func placeAxis(start: Int, length: Int, size: Int, base: Int, offset: Int)
        -> (Int, Int)
    {
        let end = start + length
        let desiredStart = base + offset
        let desiredEnd = desiredStart + size

        let clippedStart = max(desiredStart, start)
        let clippedEnd = min(desiredEnd, end)
        if size == length && clippedStart < clippedEnd {
            return (clippedStart, clippedEnd - clippedStart)
        }

        let maxStart = end - size
        return (min(max(desiredStart, start), maxStart), size)
    }
}

/// Where `hide_behavior = "offscreen"` parks a window.
///
/// macOS refuses to move a window fully off every display, so the window's top-left corner is
/// pushed into the bottom-right corner of the right-most display, leaving a one-pixel sliver.
public func offscreenRect(for window: Rect, screens: [ScreenInfo]) -> Rect {
    guard
        let target = screens.max(by: {
            ($0.frame.maxX, $0.frame.maxY) < ($1.frame.maxX, $1.frame.maxY)
        })
    else {
        return window
    }
    return Rect(
        x: target.frame.maxX - 1, y: target.frame.maxY - 1, width: window.width,
        height: window.height)
}
