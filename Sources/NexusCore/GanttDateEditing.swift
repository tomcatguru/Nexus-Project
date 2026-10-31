import Foundation

public enum GanttDateDragMode: Sendable, Hashable {
    case resizeStart
    case resizeEnd
    case move
}

public enum GanttDateEditing {
    /// Applies a horizontal, whole-day drag while preserving a valid inclusive date range.
    public static func applying(
        dayDelta: Int,
        mode: GanttDateDragMode,
        to item: GanttItem,
        calendar: Calendar = .autoupdatingCurrent
    ) -> GanttItem {
        guard dayDelta != 0 else { return item }
        var result = item

        switch mode {
        case .resizeStart:
            let candidate = calendar.date(byAdding: .day, value: dayDelta, to: item.startDate) ?? item.startDate
            result.startDate = min(candidate, item.endDate)
        case .resizeEnd:
            let candidate = calendar.date(byAdding: .day, value: dayDelta, to: item.endDate) ?? item.endDate
            result.endDate = max(candidate, item.startDate)
        case .move:
            result.startDate = calendar.date(byAdding: .day, value: dayDelta, to: item.startDate) ?? item.startDate
            result.endDate = calendar.date(byAdding: .day, value: dayDelta, to: item.endDate) ?? item.endDate
        }
        return result
    }
}
