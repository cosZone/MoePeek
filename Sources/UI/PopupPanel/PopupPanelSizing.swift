import AppKit

struct PopupResultLayout: Equatable {
    var contentHeight: CGFloat?
    var viewportHeight: CGFloat?
    var containerHeight: CGFloat?
}

enum PopupPanelSizing {
    static func frameToFit(
        currentFrame: NSRect,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        measuredContainerHeight: CGFloat,
        baselineHeight: CGFloat,
        maximumHeight: CGFloat,
        visibleFrame: NSRect
    ) -> NSRect {
        let padding: CGFloat = 8
        let chromeHeight = max(measuredContainerHeight - viewportHeight, 0)
        let desiredHeight = max(baselineHeight, chromeHeight + contentHeight)
        let screenLimit = max(visibleFrame.height - 2 * padding, 0)
        let height = min(desiredHeight, maximumHeight, screenLimit)
        let top = currentFrame.maxY
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - height - padding
        let y = maxY >= minY ? min(max(top - height, minY), maxY) : minY
        return NSRect(x: currentFrame.minX, y: y, width: currentFrame.width, height: height)
    }
}
