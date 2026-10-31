import Foundation
import CoreGraphics

public struct GanttBarInteractionRegions {
    public let start: CGRect
    public let move: CGRect
    public let end: CGRect

    public init(start: CGRect, move: CGRect, end: CGRect) {
        self.start = start
        self.move = move
        self.end = end
    }
}

public enum GanttTimelineGeometry {
    public static func barRect(
        startDay: Int,
        duration: Int,
        row: Int,
        dayWidth: CGFloat,
        rowHeight: CGFloat,
        headerHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: CGFloat(startDay) * dayWidth + 3,
            y: headerHeight + CGFloat(row) * rowHeight + 7,
            width: max(8, CGFloat(max(duration, 1)) * dayWidth - 6),
            height: rowHeight - 14
        )
    }

    public static func interactionRegions(
        for rect: CGRect,
        zoomScale: CGFloat
    ) -> GanttBarInteractionRegions {
        let scale = max(zoomScale, 0.01)
        let outsidePadding = 4 / scale
        let preferredCapWidth = max(rect.height / 2, 10 / scale)
        let capWidth = min(preferredCapWidth, rect.width * 0.35)
        let expandedY = rect.minY - 3 / scale
        let expandedHeight = rect.height + 6 / scale

        return GanttBarInteractionRegions(
            start: CGRect(
                x: rect.minX - outsidePadding,
                y: expandedY,
                width: capWidth + outsidePadding,
                height: expandedHeight
            ),
            move: CGRect(
                x: rect.minX + capWidth,
                y: expandedY,
                width: max(rect.width - capWidth * 2, 1),
                height: expandedHeight
            ),
            end: CGRect(
                x: rect.maxX - capWidth,
                y: expandedY,
                width: capWidth + outsidePadding,
                height: expandedHeight
            )
        )
    }

    public static func dragMode(
        at point: CGPoint,
        in regions: GanttBarInteractionRegions
    ) -> GanttDateDragMode? {
        if regions.start.contains(point) { return .resizeStart }
        if regions.end.contains(point) { return .resizeEnd }
        if regions.move.contains(point) { return .move }
        return nil
    }
}
