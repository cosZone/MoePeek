import AppKit
import Testing
@testable import MoePeek

@Suite struct PopupPanelSizingTests {
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

    @Test func shortResultStaysAtBaselineAndKeepsTopEdge() {
        let current = NSRect(x: 120, y: 300, width: 450, height: 350)

        let result = PopupPanelSizing.frameToFit(
            currentFrame: current,
            contentHeight: 100,
            viewportHeight: 250,
            measuredContainerHeight: 350,
            baselineHeight: 350,
            maximumHeight: 800,
            visibleFrame: visibleFrame
        )

        #expect(result.height == 350)
        #expect(result.maxY == current.maxY)
        #expect(result.origin.x == current.origin.x)
    }

    @Test func longResultGrowsToFitContentAndKeepsTopEdge() {
        let current = NSRect(x: 120, y: 300, width: 450, height: 350)

        let result = PopupPanelSizing.frameToFit(
            currentFrame: current,
            contentHeight: 500,
            viewportHeight: 250,
            measuredContainerHeight: 350,
            baselineHeight: 350,
            maximumHeight: 800,
            visibleFrame: visibleFrame
        )

        #expect(result.height == 600) // 100pt chrome + 500pt result content
        #expect(result.maxY == current.maxY)
        #expect(result.origin.x == current.origin.x)
    }

    @Test func growthIsCappedByMaximumAndViewportAndClampedOnScreen() {
        let current = NSRect(x: 120, y: 100, width: 450, height: 350)
        let smallVisibleFrame = NSRect(x: 0, y: 0, width: 800, height: 500)

        let screenCapped = PopupPanelSizing.frameToFit(
            currentFrame: current,
            contentHeight: 2_000,
            viewportHeight: 250,
            measuredContainerHeight: 350,
            baselineHeight: 350,
            maximumHeight: 800,
            visibleFrame: smallVisibleFrame
        )
        #expect(screenCapped.height == 484) // 500pt viewport minus 8pt top/bottom padding
        #expect(screenCapped.minY == 8)
        #expect(screenCapped.maxY <= smallVisibleFrame.maxY - 8)

        let maximumCapped = PopupPanelSizing.frameToFit(
            currentFrame: current,
            contentHeight: 2_000,
            viewportHeight: 250,
            measuredContainerHeight: 350,
            baselineHeight: 350,
            maximumHeight: 420,
            visibleFrame: visibleFrame
        )
        #expect(maximumCapped.height == 420)
        #expect(maximumCapped.maxY == current.maxY)
    }

    @Test func laterShortResultShrinksBackToBaseline() {
        let tallCurrent = NSRect(x: 120, y: 50, width: 450, height: 600)

        let result = PopupPanelSizing.frameToFit(
            currentFrame: tallCurrent,
            contentHeight: 100,
            viewportHeight: 500,
            measuredContainerHeight: 600,
            baselineHeight: 350,
            maximumHeight: 800,
            visibleFrame: visibleFrame
        )

        #expect(result.height == 350)
        #expect(result.maxY == tallCurrent.maxY)
        #expect(result.origin.x == tallCurrent.origin.x)
    }

    @Test func usesMeasuredLayoutWhenPanelFrameHasAlreadyGrown() {
        let current = NSRect(x: 120, y: 50, width: 450, height: 600)

        let result = PopupPanelSizing.frameToFit(
            currentFrame: current,
            contentHeight: 550,
            viewportHeight: 250,
            measuredContainerHeight: 350,
            baselineHeight: 350,
            maximumHeight: 800,
            visibleFrame: visibleFrame
        )

        #expect(result.height == 650)
    }
}
