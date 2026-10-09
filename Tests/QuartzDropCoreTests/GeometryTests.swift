import Testing

@testable import QuartzDropCore

@Suite struct GeometryTests {
    let main = ScreenInfo(
        name: "Main", frame: Rect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875))

    func place(
        _ width: PlacementMetric, _ height: PlacementMetric, _ position: PlacementPosition,
        offsetX: PlacementMetric = .pixels(0), offsetY: PlacementMetric = .pixels(0),
        on screen: ScreenInfo? = nil
    ) -> Rect {
        (screen ?? main).placementRect(
            PlacementConfig(
                width: width, height: height, position: position, offsetX: offsetX,
                offsetY: offsetY))
    }

    @Test func defaultFillsVisibleFrame() {
        #expect(
            main.placementRect(PlacementConfig()) == Rect(x: 0, y: 25, width: 720 * 2, height: 875))
    }

    @Test func halfLeftAndRight() {
        #expect(
            place(.percent(50), .percent(100), .left) == Rect(x: 0, y: 25, width: 720, height: 875))
        #expect(
            place(.percent(50), .percent(100), .right)
                == Rect(x: 720, y: 25, width: 720, height: 875))
    }

    @Test func center() {
        #expect(
            place(.percent(50), .percent(50), .center)
                == Rect(x: 360, y: 244, width: 720, height: 437))
    }

    @Test func topFortyPercent() {
        #expect(
            place(.percent(100), .percent(40), .top) == Rect(x: 0, y: 25, width: 1440, height: 350))
    }

    @Test func bottomRight() {
        #expect(
            place(.percent(50), .percent(50), .bottomRight)
                == Rect(x: 720, y: 463, width: 720, height: 437))
    }

    @Test func pixelSizes() {
        #expect(
            place(.pixels(800), .pixels(600), .center)
                == Rect(x: 320, y: 162, width: 800, height: 600))
        #expect(
            place(.pixels(800), .pixels(600), .bottomLeft)
                == Rect(x: 0, y: 300, width: 800, height: 600))
    }

    @Test func offsets() {
        #expect(
            place(.pixels(400), .pixels(300), .topLeft, offsetX: .pixels(10), offsetY: .pixels(20))
                == Rect(x: 10, y: 45, width: 400, height: 300))
        #expect(
            place(
                .pixels(400), .pixels(300), .topLeft, offsetX: .percent(10), offsetY: .percent(10))
                == Rect(x: 144, y: 25 + 87, width: 400, height: 300))
    }

    @Test func offsetsClampInsideVisibleArea() {
        #expect(
            place(
                .pixels(400), .pixels(300), .topLeft, offsetX: .pixels(5000), offsetY: .pixels(5000)
            )
                == Rect(x: 1040, y: 600, width: 400, height: 300))
        #expect(
            place(
                .pixels(400), .pixels(300), .bottomRight, offsetX: .pixels(-5000),
                offsetY: .pixels(-5000))
                == Rect(x: 0, y: 25, width: 400, height: 300))
    }

    @Test func fullSizeWithOffsetShrinksInsteadOfMoving() {
        #expect(
            place(.percent(100), .percent(100), .topLeft, offsetX: .pixels(10))
                == Rect(x: 10, y: 25, width: 1430, height: 875))
    }

    @Test func secondaryScreenWithNegativeOrigin() {
        let left = ScreenInfo(
            name: "Left", frame: Rect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: Rect(x: -1920, y: 0, width: 1920, height: 1055))
        #expect(
            place(.percent(50), .percent(100), .right, on: left)
                == Rect(x: -960, y: 0, width: 960, height: 1055))
        #expect(
            place(.percent(50), .percent(50), .center, on: left)
                == Rect(x: -1440, y: 264, width: 960, height: 527))
        #expect(
            place(.percent(50), .percent(100), .left, on: left)
                == Rect(x: -1920, y: 0, width: 960, height: 1055))
    }

    @Test func validatePlacement() throws {
        try main.validatePlacement(PlacementConfig())
        try main.validatePlacement(PlacementConfig(width: .pixels(1440), height: .pixels(875)))

        func message(_ placement: PlacementConfig) throws -> String {
            try #require(throws: ConfigError.self) { try main.validatePlacement(placement) }
                .message
        }
        #expect(try message(PlacementConfig(width: .pixels(2000))).contains("exceeds screen width"))
        #expect(
            try message(PlacementConfig(height: .pixels(1000))).contains("exceeds screen height"))
        #expect(try message(PlacementConfig(width: .pixels(0))).contains("at least 1"))
        #expect(try message(PlacementConfig(height: .percent(0))).contains("at least 1"))
    }

    @Test func resolveMetric() {
        #expect(ScreenInfo.resolve(.percent(33), axis: 100) == 33)
        #expect(ScreenInfo.resolve(.pixels(7), axis: 100) == 7)
        #expect(ScreenInfo.resolve(.percent(50), axis: 875) == 437)
    }

    @Test func offscreenPicksRightMostScreen() {
        let right = ScreenInfo(
            name: "Right", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1055))
        let window = Rect(x: 100, y: 100, width: 640, height: 480)
        #expect(
            offscreenRect(for: window, screens: [right, main])
                == Rect(x: 3359, y: 1079, width: 640, height: 480))
    }

    @Test func offscreenPicksBottomMostWhenSameRightEdge() {
        let below = ScreenInfo(
            name: "Below", frame: Rect(x: 0, y: 900, width: 1440, height: 900),
            visibleFrame: Rect(x: 0, y: 900, width: 1440, height: 900))
        let window = Rect(x: 5, y: 5, width: 300, height: 200)
        #expect(
            offscreenRect(for: window, screens: [main, below])
                == Rect(x: 1439, y: 1799, width: 300, height: 200))
        #expect(
            offscreenRect(for: window, screens: [below, main])
                == Rect(x: 1439, y: 1799, width: 300, height: 200))
    }

    @Test func offscreenWithoutScreensReturnsInput() {
        let window = Rect(x: 5, y: 5, width: 300, height: 200)
        #expect(offscreenRect(for: window, screens: []) == window)
    }

    @Test func rectContains() {
        let rect = Rect(x: 10, y: 20, width: 100, height: 50)
        #expect(rect.contains(Point(x: 10, y: 20)))
        #expect(rect.contains(Point(x: 109, y: 69)))
        #expect(!rect.contains(Point(x: 110, y: 20)))
        #expect(!rect.contains(Point(x: 10, y: 70)))
        #expect(!rect.contains(Point(x: 9, y: 20)))
    }

    @Test func rectOverlap() {
        let a = Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(a.overlapArea(with: Rect(x: 50, y: 50, width: 100, height: 100)) == 2500)
        #expect(a.overlapArea(with: Rect(x: 100, y: 0, width: 50, height: 50)) == 0)
        #expect(a.overlapArea(with: Rect(x: 500, y: 500, width: 5, height: 5)) == 0)
        #expect(a.overlapArea(with: Rect(x: 10, y: 10, width: 10, height: 10)) == 100)
        #expect(a.overlapArea(with: a) == 10000)
    }
}
