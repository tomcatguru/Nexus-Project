import SwiftUI
import Combine
import UniformTypeIdentifiers
import NexusCore

struct GanttBoard: View {
    @EnvironmentObject private var store: GanttStore
    private let rowHeight: CGFloat = 36
    private let headerHeight: CGFloat = 52
    private let verticalBufferRows = 60
    private let minimumLabelWidth: CGFloat = 230
    private let maximumLabelWidth: CGFloat = 560
    private let minimumTimelineWidth: CGFloat = 200

    @State private var rowCapacity = 60
    @State private var currentLabelWidth: CGFloat = 300
    @State private var didRestoreLabelWidth = false
    @StateObject private var pointerRouter = TimelinePointerRouter()
    @AppStorage("gantt.taskPanel.width") private var savedLabelWidth = 300.0

    var body: some View {
        let visible = store.visibleItems
        let offsetRowCapacity = Int(ceil(max(store.viewportOffset.y, 0) / rowHeight)) + verticalBufferRows
        let effectiveRowCapacity = max(rowCapacity, offsetRowCapacity, visible.count, 1)
        let range = TimelineRange(items: store.items)
        let dayWidth = store.timeScale.dayWidth
        let canvasHeight = headerHeight + CGFloat(effectiveRowCapacity) * rowHeight
        let timelineWidth = max(600, CGFloat(range.dayCount) * dayWidth)

        GeometryReader { geometry in
            let maximumAvailableLabelWidth = max(
                minimumLabelWidth,
                min(maximumLabelWidth, geometry.size.width - minimumTimelineWidth)
            )
            let labelWidth = min(
                max(CGFloat(savedLabelWidth), minimumLabelWidth),
                maximumAvailableLabelWidth
            )
            let effectiveLabelWidth = min(
                max(currentLabelWidth, minimumLabelWidth),
                maximumAvailableLabelWidth
            )
            let timelineViewportWidth = max(1, geometry.size.width - effectiveLabelWidth)
            let minimumZoom = minimumZoom(
                viewportWidth: timelineViewportWidth,
                documentWidth: timelineWidth
            )
            let zoomScale = CGFloat(store.zoom)

            HSplitView {
                ZStack(alignment: .topLeading) {
                    LabelColumn(
                        items: visible,
                        rowHeight: rowHeight * zoomScale,
                        headerHeight: headerHeight * zoomScale
                    )
                    .frame(height: canvasHeight * zoomScale, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(y: -store.viewportOffset.y * zoomScale)
                }
                .frame(
                    minWidth: didRestoreLabelWidth ? minimumLabelWidth : labelWidth,
                    idealWidth: labelWidth,
                    maxWidth: didRestoreLabelWidth ? maximumAvailableLabelWidth : labelWidth,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .background(Color(nsColor: .textBackgroundColor))
                .onGeometryChange(for: CGFloat.self) { panelGeometry in
                    panelGeometry.size.width
                } action: { width in
                    guard width > 0 else { return }
                    currentLabelWidth = width
                    if didRestoreLabelWidth, abs(savedLabelWidth - Double(width)) > 0.5 {
                        savedLabelWidth = Double(width)
                    }
                }
                .clipped()

                PersistentScrollView(
                    magnification: $store.zoom,
                    contentOffset: $store.viewportOffset,
                    minimumMagnification: minimumZoom,
                    onPointerEvent: pointerRouter.send
                ) {
                    TimelineCanvas(
                        items: visible,
                        range: range,
                        scale: store.timeScale,
                        dayWidth: dayWidth,
                        rowHeight: rowHeight,
                        headerHeight: headerHeight,
                        magnification: store.zoom,
                        pointerRouter: pointerRouter,
                        selectedID: store.selectedID,
                        onSelect: { store.selectedID = $0 },
                        onChangeDates: { id, startDate, endDate in
                            store.updateDates(for: id, startDate: startDate, endDate: endDate)
                        }
                    )
                    .frame(width: timelineWidth, height: canvasHeight)
                }
                .frame(minWidth: minimumTimelineWidth, maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                currentLabelWidth = labelWidth
                store.setMinimumZoom(minimumZoom)
                DispatchQueue.main.async {
                    didRestoreLabelWidth = true
                }
            }
            .onChange(of: minimumZoom) { _, value in
                store.setMinimumZoom(value)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { expandCanvas(for: store.viewportOffset) }
        .onChange(of: store.viewportOffset) { _, offset in
            expandCanvas(for: offset)
        }
    }

    private func expandCanvas(for offset: CGPoint) {
        let requiredRows = Int(ceil(max(offset.y, 0) / rowHeight)) + verticalBufferRows
        if requiredRows > rowCapacity {
            rowCapacity = requiredRows
        }
    }

    private func minimumZoom(viewportWidth: CGFloat, documentWidth: CGFloat) -> Double {
        guard viewportWidth > 0, documentWidth > 0 else { return 0.65 }
        return min(2, max(0.65, Double(viewportWidth / documentWidth)))
    }
}

@MainActor
private final class TimelinePointerRouter: ObservableObject {
    let events = PassthroughSubject<ScrollDocumentPointerEvent, Never>()

    func send(_ event: ScrollDocumentPointerEvent) {
        events.send(event)
    }
}

private struct LabelColumn: View {
    @EnvironmentObject private var store: GanttStore
    let items: [VisibleGanttItem]
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    @State private var dropTargetID: UUID?
    @State private var draggedTaskID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("작업")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("기간")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: headerHeight)
            .background(.bar)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, visible in
                taskRow(
                    for: visible,
                    showsSeparator: showsSeparator(after: index)
                )
                    .modifier(
                        TaskDragSourceModifier(
                            item: visible.item,
                            draggedTaskID: $draggedTaskID
                        )
                    )
                    .onDrop(
                        of: [UTType.text],
                        delegate: TaskHierarchyDropDelegate(
                            targetID: visible.id,
                            store: store,
                            draggedTaskID: $draggedTaskID,
                            dropTargetID: $dropTargetID
                        )
                    )
            }
        }
        .overlay(alignment: .trailing) { Divider() }
    }

    private func taskRow(
        for visible: VisibleGanttItem,
        showsSeparator: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(visible.depth) * 14)
            if store.items.contains(where: { $0.parentID == visible.id }) {
                Button { store.toggleExpanded(visible.id) } label: {
                    Image(systemName: visible.item.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.bold())
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: visible.item.kind == .project ? "folder.fill" : "checkmark.square")
                .foregroundStyle(visible.item.kind == .project ? .blue : .secondary)
            Text(visible.item.title)
                .fontWeight(visible.item.kind == .project ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            Text(dateRange(for: visible.item))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            if visible.item.kind == .task {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                    .help("드래그하여 포함 관계 변경")
            } else {
                Color.clear.frame(width: 10)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .background {
            if dropTargetID == visible.id {
                Color.accentColor.opacity(0.2)
            } else if store.selectedID == visible.id {
                Color.accentColor.opacity(0.12)
            }
        }
        .overlay {
            if dropTargetID == visible.id {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(2)
            }
        }
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.65))
                    .frame(height: 0.5)
            }
        }
        .onTapGesture { store.selectedID = visible.id }
    }

    private func showsSeparator(after index: Int) -> Bool {
        guard items.indices.contains(index + 1) else { return true }
        // A parent and its first child form one visual group. Drawing a rule
        // between them looks like a stray insertion marker and breaks the
        // hierarchy's visual continuity.
        return items[index + 1].depth <= items[index].depth
    }

    private func dateRange(for item: GanttItem) -> String {
        let start = item.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = item.endDate.formatted(.dateTime.month(.abbreviated).day())
        return start == end ? start : "\(start) – \(end)"
    }
}

private struct TaskDragSourceModifier: ViewModifier {
    let item: GanttItem
    @Binding var draggedTaskID: UUID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if item.kind == .task {
            content.onDrag {
                draggedTaskID = item.id
                return NSItemProvider(object: item.id.uuidString as NSString)
            } preview: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.square")
                    Text(item.title)
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            }
        } else {
            content
        }
    }
}

private struct TaskHierarchyDropDelegate: DropDelegate {
    let targetID: UUID
    let store: GanttStore
    @Binding var draggedTaskID: UUID?
    @Binding var dropTargetID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedTaskID else { return false }
        return draggedTaskID != targetID
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        dropTargetID = targetID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID {
            dropTargetID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedTaskID else { return false }
        let didMove = store.reparentTask(draggedTaskID, to: targetID)
        self.draggedTaskID = nil
        dropTargetID = nil
        return didMove
    }
}

private struct TimelineRange {
    let start: Date
    let end: Date
    let dayCount: Int

    init(items: [GanttItem], calendar: Calendar = .autoupdatingCurrent) {
        let today = calendar.startOfDay(for: .now)
        let earliest = items.map(\.startDate).min() ?? today
        let latest = items.map(\.endDate).max() ?? today
        start = calendar.startOfDay(for: earliest)
        let lastItemDay = calendar.startOfDay(for: latest)
        end = calendar.date(byAdding: .month, value: 6, to: lastItemDay)!
        dayCount = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }
}

private struct TimelineCanvas: View {
    let items: [VisibleGanttItem]
    let range: TimelineRange
    let scale: GanttTimeScale
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    let magnification: Double
    @ObservedObject var pointerRouter: TimelinePointerRouter
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onChangeDates: (UUID, Date, Date) -> Void
    private let calendar = Calendar.autoupdatingCurrent
    private var zoomScale: CGFloat { max(CGFloat(magnification), 0.65) }

    @State private var hoverTarget: BarTarget?
    @State private var dragSession: DragSession?
    @State private var pendingDragTarget: BarTarget?

    var body: some View {
        Canvas { context, size in
            drawBackground(context: &context, size: size)
            drawHeaders(context: &context, size: size)
            drawDependencies(context: &context)
            drawBars(context: &context)
        }
        .contentShape(Rectangle())
        .onReceive(pointerRouter.events, perform: handlePointerEvent)
        .onChange(of: selectedID) { _, newSelection in
            if hoverTarget?.id != newSelection {
                hoverTarget = nil
                NSCursor.arrow.set()
            }
            if dragSession?.target.id != newSelection {
                dragSession = nil
            }
        }
        .onDisappear { NSCursor.arrow.set() }
        .accessibilityLabel("간트 차트 타임라인")
        .accessibilityHint("바 가장자리를 드래그해 날짜를 변경하거나 중앙을 드래그해 일정을 이동합니다")
    }

    private func handlePointerEvent(_ event: ScrollDocumentPointerEvent) {
        switch event {
        case .moved(let location):
            guard dragSession == nil else { return }
            let target = hoverTarget(at: location)
            if target != hoverTarget {
                hoverTarget = target
                setCursor(for: target?.mode)
            }
        case .exited:
            guard dragSession == nil else { return }
            hoverTarget = nil
            pendingDragTarget = nil
            NSCursor.arrow.set()
        case .down(let location):
            guard dragSession == nil else { return }
            pendingDragTarget = hoverTarget(at: location)
            if let item = item(at: location) {
                onSelect(item.id)
            }
        case .dragged(_, let translation):
            let target = dragSession?.target ?? pendingDragTarget
            guard let target else { return }
            handleDragChanged(horizontalTranslation: translation.width, target: target)
        case .up(let location):
            if dragSession != nil {
                handleDragEnded()
            }
            pendingDragTarget = nil
            hoverTarget = hoverTarget(at: location)
            setCursor(for: hoverTarget?.mode)
        }
    }

    private func item(at location: CGPoint) -> VisibleGanttItem? {
        for (row, visible) in items.enumerated().reversed() {
            if barRect(for: visible.item, row: row).contains(location) {
                return visible
            }
        }
        return nil
    }

    private func hoverTarget(at location: CGPoint) -> BarTarget? {
        guard let selectedID,
              let entry = items.enumerated().first(where: { $0.element.id == selectedID }) else {
            return nil
        }
        let regions = GanttTimelineGeometry.interactionRegions(
            for: barRect(for: entry.element.item, row: entry.offset),
            zoomScale: zoomScale
        )
        guard let mode = GanttTimelineGeometry.dragMode(at: location, in: regions) else { return nil }
        return BarTarget(id: selectedID, mode: mode)
    }

    private func handleDragChanged(horizontalTranslation: CGFloat, target: BarTarget) {
        guard target.id == selectedID else { return }
        if dragSession == nil {
            guard let item = items.first(where: { $0.id == target.id })?.item else { return }
            dragSession = DragSession(target: target, originalItem: item, previewItem: item, dayDelta: 0)
            hoverTarget = target
            setCursor(for: target.mode, isDragging: true)
        }

        guard var session = dragSession else { return }
        let dayDelta = Int((horizontalTranslation / dayWidth).rounded())
        guard dayDelta != session.dayDelta else { return }
        session.dayDelta = dayDelta
        session.previewItem = GanttDateEditing.applying(
            dayDelta: dayDelta,
            mode: session.target.mode,
            to: session.originalItem,
            calendar: calendar
        )
        dragSession = session
    }

    private func handleDragEnded() {
        if let session = dragSession, session.target.id == selectedID {
            if session.dayDelta != 0 {
                onChangeDates(session.target.id, session.previewItem.startDate, session.previewItem.endDate)
            }
            dragSession = nil
            hoverTarget = nil
            NSCursor.arrow.set()
            onSelect(session.target.id)
            return
        }
    }

    private func setCursor(for mode: GanttDateDragMode?, isDragging: Bool = false) {
        switch mode {
        case .resizeStart, .resizeEnd:
            NSCursor.resizeLeftRight.set()
        case .move:
            (isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
        case nil:
            NSCursor.arrow.set()
        }
    }

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .textBackgroundColor)))
        let today = calendar.startOfDay(for: .now)
        for day in 0..<range.dayCount {
            let date = calendar.date(byAdding: .day, value: day, to: range.start)!
            let x = CGFloat(day) * dayWidth
            if dayWidth >= 12, calendar.isDateInWeekend(date) {
                context.fill(Path(CGRect(x: x, y: headerHeight, width: dayWidth, height: size.height - headerHeight)), with: .color(.secondary.opacity(0.055)))
            }
            if scale == .days, calendar.isDate(date, inSameDayAs: today) {
                context.fill(
                    Path(CGRect(x: x, y: headerHeight, width: dayWidth, height: size.height - headerHeight)),
                    with: .color(.orange.opacity(0.11))
                )
            }
            guard shouldDrawVerticalGrid(on: date) else { continue }
            var grid = Path()
            grid.move(to: CGPoint(x: x, y: headerHeight))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(grid, with: .color(.secondary.opacity(0.14)), lineWidth: 0.5)
        }
        let visibleGridRows = max(
            items.count,
            Int(ceil(max(size.height - headerHeight, 0) / rowHeight))
        )
        for row in 0...visibleGridRows {
            let y = headerHeight + CGFloat(row) * rowHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.secondary.opacity(0.16)), lineWidth: 0.5)
        }
        let todayOffset = calendar.dateComponents([.day], from: range.start, to: today).day ?? -1
        if scale != .days, todayOffset >= 0, todayOffset < range.dayCount {
            let x = CGFloat(todayOffset) * dayWidth + dayWidth / 2
            var line = Path()
            line.move(to: CGPoint(x: x, y: headerHeight - 8))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(.red.opacity(0.7)), lineWidth: 1.5)
        }
    }

    private func drawHeaders(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: headerHeight)), with: .color(Color(nsColor: .windowBackgroundColor)))
        if scale == .days {
            drawDaysHeader(context: &context, size: size)
            drawHeaderDivider(context: &context, size: size)
            return
        }

        let monthFormat = Date.FormatStyle().month(.wide).year()
        let yearFormat = Date.FormatStyle().year()
        let shortWeekday = DateFormatter()
        shortWeekday.locale = Locale(identifier: "en_US_POSIX")
        shortWeekday.calendar = calendar
        shortWeekday.dateFormat = "EEE"
        var lastMonth = -1
        var lastYear = -1
        for day in 0..<range.dayCount {
            let date = calendar.date(byAdding: .day, value: day, to: range.start)!
            let x = CGFloat(day) * dayWidth
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)

            if scale == .months || scale == .years {
                if year != lastYear {
                    context.draw(
                        Text(date.formatted(yearFormat)).font(.caption.bold()).foregroundStyle(.secondary),
                        at: CGPoint(x: x + 6, y: 13),
                        anchor: .leading
                    )
                    lastYear = year
                }
            } else if month != lastMonth {
                context.draw(
                    Text(date.formatted(monthFormat)).font(.caption.bold()).foregroundStyle(.secondary),
                    at: CGPoint(x: x + 6, y: 13),
                    anchor: .leading
                )
                lastMonth = month
            }

            if let label = lowerHeaderLabel(for: date, shortWeekday: shortWeekday) {
                context.draw(
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: x + max(dayWidth / 2, 4), y: 37),
                    anchor: scale == .months || scale == .years ? .leading : .center
                )
            }
        }
        drawHeaderDivider(context: &context, size: size)
    }

    private func drawDaysHeader(context: inout GraphicsContext, size: CGSize) {
        let weekCalendar = mondayBasedCalendar
        let today = calendar.startOfDay(for: .now)
        let weekRowHeight: CGFloat = 25

        for day in 0..<range.dayCount {
            let date = calendar.date(byAdding: .day, value: day, to: range.start)!
            let x = CGFloat(day) * dayWidth
            let isToday = calendar.isDate(date, inSameDayAs: today)

            if isToday {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: dayWidth, height: headerHeight)),
                    with: .color(.orange.opacity(0.17))
                )
            }

            context.draw(
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption2.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.orange : Color.secondary),
                at: CGPoint(x: x + dayWidth / 2, y: 39),
                anchor: .center
            )

            guard day == 0 || weekCalendar.component(.weekday, from: date) == 2 else { continue }
            let weekStart = startOfWeek(containing: date, calendar: weekCalendar)
            guard let weekEnd = weekCalendar.date(byAdding: .day, value: 6, to: weekStart) else { continue }
            let startOffset = calendar.dateComponents([.day], from: range.start, to: weekStart).day ?? day
            let bandX = CGFloat(startOffset) * dayWidth
            let bandWidth = dayWidth * 7

            context.draw(
                Text("\(weekCalendar.component(.weekOfYear, from: weekStart))")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary),
                at: CGPoint(x: bandX + 5, y: 12),
                anchor: .leading
            )
            context.draw(
                Text(weekRangeLabel(from: weekStart, through: weekEnd))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: bandX + bandWidth / 2, y: 12),
                anchor: .center
            )

            var weekBoundary = Path()
            weekBoundary.move(to: CGPoint(x: bandX, y: 0))
            weekBoundary.addLine(to: CGPoint(x: bandX, y: headerHeight))
            context.stroke(weekBoundary, with: .color(.secondary.opacity(0.2)), lineWidth: 0.75)
        }

        var rowDivider = Path()
        rowDivider.move(to: CGPoint(x: 0, y: weekRowHeight))
        rowDivider.addLine(to: CGPoint(x: size.width, y: weekRowHeight))
        context.stroke(rowDivider, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
    }

    private func drawHeaderDivider(context: inout GraphicsContext, size: CGSize) {
        var divider = Path()
        divider.move(to: CGPoint(x: 0, y: headerHeight))
        divider.addLine(to: CGPoint(x: size.width, y: headerHeight))
        context.stroke(divider, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
    }

    private var mondayBasedCalendar: Calendar {
        var value = calendar
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func weekRangeLabel(from start: Date, through end: Date) -> String {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.calendar = calendar
        monthFormatter.dateFormat = "MMM"

        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let startMonth = monthFormatter.string(from: start)
        let endMonth = monthFormatter.string(from: end)

        if calendar.component(.month, from: start) == calendar.component(.month, from: end) {
            return "\(startDay) – \(endDay) \(endMonth)"
        }
        return "\(startDay) \(startMonth) – \(endDay) \(endMonth)"
    }

    private func shouldDrawVerticalGrid(on date: Date) -> Bool {
        switch scale {
        case .today, .days:
            true
        case .weeks:
            calendar.component(.weekday, from: date) == 2
        case .months:
            calendar.component(.day, from: date) == 1
        case .years:
            calendar.component(.day, from: date) == 1
                && calendar.component(.month, from: date) == 1
        }
    }

    private func lowerHeaderLabel(for date: Date, shortWeekday: DateFormatter) -> String? {
        let day = calendar.component(.day, from: date)
        let weekday = calendar.component(.weekday, from: date)

        switch scale {
        case .today:
            return "\(day) \(shortWeekday.string(from: date))"
        case .days:
            return weekday == 2 ? "\(day)(Monday)" : nil
        case .weeks:
            guard weekday == 2 else { return nil }
            let week = calendar.component(.weekOfYear, from: date)
            return "W\(week) · \(day)"
        case .months, .years:
            guard day == 1 else { return nil }
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    /// Draws finish-to-start dependencies beneath the bars. Keeping this in a
    /// separate layer prevents a connector from obscuring a task label or the
    /// selected bar while preserving a visible arrow immediately before the
    /// target's leading edge.
    private func drawDependencies(context: inout GraphicsContext) {
        let rendered = items.enumerated().map { row, visible in
            let item = renderedItem(for: visible)
            return (id: visible.id, row: row, item: item, rect: barRect(for: item, row: row))
        }
        let renderedByID = Dictionary(uniqueKeysWithValues: rendered.map { ($0.id, $0) })
        let lineWidth = 1.25 / zoomScale
        let stub = 12 / zoomScale
        let arrowGap = 3 / zoomScale
        let arrowLength = 6 / zoomScale
        let arrowHalfHeight = 3.5 / zoomScale
        let connectorColor = Color(nsColor: .tertiaryLabelColor).opacity(0.9)

        for target in rendered {
            for dependencyID in target.item.dependencyIDs {
                guard let source = renderedByID[dependencyID] else { continue }

                let targetPoint = CGPoint(
                    x: target.rect.minX - arrowGap,
                    y: target.rect.midY
                )
                var path = Path()

                if source.rect.maxX + stub + arrowLength < target.rect.minX {
                    // Standard finish-to-start dependency: leave the source's
                    // right edge, turn once, then enter the target from left.
                    let turnX = min(
                        source.rect.maxX + stub,
                        target.rect.minX - stub
                    )
                    path.move(to: CGPoint(x: source.rect.maxX, y: source.rect.midY))
                    path.addLine(to: CGPoint(x: turnX, y: source.rect.midY))
                    path.addLine(to: CGPoint(x: turnX, y: target.rect.midY))
                    path.addLine(to: targetPoint)
                } else {
                    // Parent/child schedules commonly overlap. A finish-edge
                    // route would run to the far right of the parent and back.
                    // Exit through the nearer horizontal edge and use the row
                    // gutter instead, matching the compact XMind-style route.
                    let approachX = target.rect.minX - stub
                    let cornerInset = min(10 / zoomScale, source.rect.width / 3)
                    let sourceExitX = min(
                        max(approachX, source.rect.minX + cornerInset),
                        source.rect.maxX - cornerInset
                    )
                    let sourceIsAbove = source.row < target.row
                    let sourceEdgeY = sourceIsAbove ? source.rect.maxY : source.rect.minY
                    let gutterY = sourceEdgeY + (sourceIsAbove ? 7 / zoomScale : -7 / zoomScale)

                    path.move(to: CGPoint(x: sourceExitX, y: sourceEdgeY))
                    path.addLine(to: CGPoint(x: sourceExitX, y: gutterY))
                    path.addLine(to: CGPoint(x: approachX, y: gutterY))
                    path.addLine(to: CGPoint(x: approachX, y: target.rect.midY))
                    path.addLine(to: targetPoint)
                }

                context.stroke(
                    path,
                    with: .color(connectorColor),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                var arrow = Path()
                arrow.move(to: CGPoint(x: target.rect.minX - 1 / zoomScale, y: target.rect.midY))
                arrow.addLine(to: CGPoint(
                    x: targetPoint.x - arrowLength,
                    y: targetPoint.y - arrowHalfHeight
                ))
                arrow.addLine(to: CGPoint(
                    x: targetPoint.x - arrowLength,
                    y: targetPoint.y + arrowHalfHeight
                ))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(connectorColor))
            }
        }
    }

    private func drawBars(context: inout GraphicsContext) {
        for (row, visible) in items.enumerated() {
            let item = renderedItem(for: visible)
            let rect = barRect(for: item, row: row)
            let base: Color = item.kind == .project ? .blue : .indigo
            let shape = Path(roundedRect: rect, cornerRadius: item.kind == .project ? 4 : rect.height / 2)
            context.fill(shape, with: .color(base.opacity(selectedID == item.id ? 0.95 : 0.72)))
            let progressRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * item.progress, height: rect.height)
            context.fill(Path(roundedRect: progressRect, cornerRadius: rect.height / 2), with: .color(.white.opacity(0.28)))
            if selectedID == item.id {
                context.stroke(shape, with: .color(.primary.opacity(0.7)), lineWidth: 2)
            }
            context.draw(Text(item.title).font(.caption2.bold()).foregroundStyle(.white), at: CGPoint(x: rect.minX + 8, y: rect.midY), anchor: .leading)
            drawInteractionIndicator(for: item, rect: rect, context: &context)
        }
    }

    private func drawInteractionIndicator(for item: GanttItem, rect: CGRect, context: inout GraphicsContext) {
        guard selectedID == item.id,
              hoverTarget?.id == item.id || dragSession?.target.id == item.id else { return }
        let activeMode = dragSession?.target.mode ?? hoverTarget?.mode

        if activeMode == .resizeStart || activeMode == .resizeEnd {
            drawResizeHandle(mode: activeMode!, item: item, rect: rect, context: &context)
        } else if activeMode == .move, rect.width > 54 {
            var moveSymbol = context.resolve(Image(systemName: "arrow.left.and.right"))
            moveSymbol.shading = .color(.white.opacity(0.9))
            context.draw(
                moveSymbol,
                at: CGPoint(x: rect.maxX - 15, y: rect.midY),
                anchor: .center
            )
        }

        if let session = dragSession,
           session.target.id == item.id,
           session.target.mode == .move,
           session.dayDelta != 0 {
            let text = "\(item.startDate.formatted(.dateTime.month().day())) – \(item.endDate.formatted(.dateTime.month().day()))"
            context.draw(
                Text(text).font(.caption.bold()).foregroundStyle(.primary),
                at: CGPoint(x: rect.midX, y: rect.minY - 8),
                anchor: .bottom
            )
        }
    }

    private func drawResizeHandle(
        mode: GanttDateDragMode,
        item: GanttItem,
        rect: CGRect,
        context: inout GraphicsContext
    ) {
        let x = mode == .resizeStart ? rect.minX : rect.maxX
        let diameter = 16 / zoomScale
        let handleRect = CGRect(
            x: x - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let handle = Path(ellipseIn: handleRect)
        context.fill(handle, with: .color(.white.opacity(0.98)))
        context.stroke(handle, with: .color(.accentColor), lineWidth: 2 / zoomScale)

        let tickOffset = 2 / zoomScale
        let tickHeight = 6 / zoomScale
        for tickX in [x - tickOffset, x + tickOffset] {
            var tick = Path()
            tick.move(to: CGPoint(x: tickX, y: rect.midY - tickHeight / 2))
            tick.addLine(to: CGPoint(x: tickX, y: rect.midY + tickHeight / 2))
            context.stroke(tick, with: .color(.accentColor), lineWidth: 1 / zoomScale)
        }

        let date = mode == .resizeStart ? item.startDate : item.endDate
        let prefix = mode == .resizeStart ? "시작" : "완료"
        let label = context.resolve(
            Text("\(prefix)  \(date.formatted(.dateTime.month().day()))")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        )
        let measured = label.measure(in: CGSize(width: 160, height: 28))
        let horizontalPadding = 6 / zoomScale
        let verticalPadding = 3 / zoomScale
        let bubbleSize = CGSize(
            width: measured.width + horizontalPadding * 2,
            height: measured.height + verticalPadding * 2
        )
        let bubbleX = mode == .resizeStart ? x : x - bubbleSize.width
        let bubbleRect = CGRect(
            x: bubbleX,
            y: rect.minY - bubbleSize.height - 6 / zoomScale,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        context.fill(
            Path(roundedRect: bubbleRect, cornerRadius: 4 / zoomScale),
            with: .color(.black.opacity(0.78))
        )
        context.draw(label, at: CGPoint(x: bubbleRect.midX, y: bubbleRect.midY), anchor: .center)
    }

    private func renderedItem(for visible: VisibleGanttItem) -> GanttItem {
        guard let session = dragSession, session.target.id == visible.id else { return visible.item }
        return session.previewItem
    }

    private func barRect(for item: GanttItem, row: Int) -> CGRect {
        let startDay = calendar.dateComponents(
            [.day],
            from: range.start,
            to: calendar.startOfDay(for: item.startDate)
        ).day ?? 0
        let duration = max(
            1,
            (calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: item.startDate),
                to: calendar.startOfDay(for: item.endDate)
            ).day ?? 0) + 1
        )
        return GanttTimelineGeometry.barRect(
            startDay: startDay,
            duration: duration,
            row: row,
            dayWidth: dayWidth,
            rowHeight: rowHeight,
            headerHeight: headerHeight
        )
    }

    private struct BarTarget: Equatable {
        let id: UUID
        let mode: GanttDateDragMode
    }

    private struct DragSession {
        let target: BarTarget
        let originalItem: GanttItem
        var previewItem: GanttItem
        var dayDelta: Int
    }
}
