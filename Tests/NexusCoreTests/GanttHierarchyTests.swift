import XCTest
@testable import NexusCore

final class GanttHierarchyTests: XCTestCase {
    func testVisibleItemsRespectsExpansionAndDepth() {
        let now = Date()
        let project = GanttItem(title: "P", kind: .project, startDate: now, endDate: now)
        let task = GanttItem(title: "T", kind: .task, startDate: now, endDate: now, parentID: project.id)
        let child = GanttItem(title: "C", kind: .task, startDate: now, endDate: now, parentID: task.id)

        let visible = GanttHierarchy.visibleItems(from: [child, task, project])
        XCTAssertEqual(visible.map(\.id), [project.id, task.id, child.id])
        XCTAssertEqual(visible.map(\.depth), [0, 1, 2])
    }

    func testCollapsedParentHidesDescendants() {
        let now = Date()
        let project = GanttItem(title: "P", kind: .project, startDate: now, endDate: now, isExpanded: false)
        let task = GanttItem(title: "T", kind: .task, startDate: now, endDate: now, parentID: project.id)
        XCTAssertEqual(GanttHierarchy.visibleItems(from: [project, task]).map(\.id), [project.id])
    }

    func testSanitizeKeepsOnlyAncestorDependencies() {
        let now = Date()
        let project = GanttItem(title: "P", kind: .project, startDate: now, endDate: now)
        let sibling = GanttItem(title: "S", kind: .task, startDate: now, endDate: now, parentID: project.id)
        let child = GanttItem(title: "C", kind: .task, startDate: now, endDate: now, parentID: sibling.id, dependencyIDs: [project.id, sibling.id, UUID()])
        let sanitized = GanttHierarchy.sanitized([project, sibling, child])
        XCTAssertEqual(Set(sanitized.first(where: { $0.id == child.id })!.dependencyIDs), Set([project.id, sibling.id]))
    }

    func testReparentingTaskMovesItUnderTargetAndUpdatesDependency() {
        let now = Date()
        let project = GanttItem(title: "P", kind: .project, startDate: now, endDate: now)
        let newParent = GanttItem(
            title: "Parent",
            kind: .task,
            startDate: now,
            endDate: now,
            parentID: project.id,
            isExpanded: false
        )
        let task = GanttItem(title: "T", kind: .task, startDate: now, endDate: now, parentID: project.id)

        let result = GanttHierarchy.reparentingTask(task.id, to: newParent.id, in: [project, newParent, task])

        XCTAssertEqual(result?.first(where: { $0.id == task.id })?.parentID, newParent.id)
        XCTAssertEqual(result?.first(where: { $0.id == task.id })?.dependencyIDs, [newParent.id])
        XCTAssertEqual(result?.first(where: { $0.id == newParent.id })?.isExpanded, true)
    }

    func testReparentingRejectsProjectsAndCycles() {
        let now = Date()
        let project = GanttItem(title: "P", kind: .project, startDate: now, endDate: now)
        let parent = GanttItem(title: "Parent", kind: .task, startDate: now, endDate: now, parentID: project.id)
        let child = GanttItem(title: "Child", kind: .task, startDate: now, endDate: now, parentID: parent.id)
        let items = [project, parent, child]

        XCTAssertNil(GanttHierarchy.reparentingTask(project.id, to: parent.id, in: items))
        XCTAssertNil(GanttHierarchy.reparentingTask(parent.id, to: child.id, in: items))
        XCTAssertNil(GanttHierarchy.reparentingTask(parent.id, to: parent.id, in: items))
    }

    func testDateDragMovesBothDatesByTheSameNumberOfDays() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let item = GanttItem(title: "T", kind: .task, startDate: start, endDate: end)

        let moved = GanttDateEditing.applying(dayDelta: 3, mode: .move, to: item, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: moved.startDate).day, 3)
        XCTAssertEqual(calendar.dateComponents([.day], from: end, to: moved.endDate).day, 3)
    }

    func testStartAndEndResizeCannotCross() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let item = GanttItem(title: "T", kind: .task, startDate: start, endDate: end)

        let startPastEnd = GanttDateEditing.applying(dayDelta: 20, mode: .resizeStart, to: item, calendar: calendar)
        let endBeforeStart = GanttDateEditing.applying(dayDelta: -20, mode: .resizeEnd, to: item, calendar: calendar)
        XCTAssertEqual(startPastEnd.startDate, end)
        XCTAssertEqual(endBeforeStart.endDate, start)
    }

    func testStartResizeChangesOnlyTheStartDate() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let item = GanttItem(title: "T", kind: .task, startDate: start, endDate: end)

        let resized = GanttDateEditing.applying(dayDelta: 2, mode: .resizeStart, to: item, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: resized.startDate).day, 2)
        XCTAssertEqual(resized.endDate, end)
    }

    func testEndResizeChangesOnlyTheEndDate() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let item = GanttItem(title: "T", kind: .task, startDate: start, endDate: end)

        let resized = GanttDateEditing.applying(dayDelta: 3, mode: .resizeEnd, to: item, calendar: calendar)
        XCTAssertEqual(resized.startDate, start)
        XCTAssertEqual(calendar.dateComponents([.day], from: end, to: resized.endDate).day, 3)
    }

    func testTimelineRowsHaveDistinctHitRects() {
        let rects = (0..<3).map {
            GanttTimelineGeometry.barRect(
                startDay: 2,
                duration: 5,
                row: $0,
                dayWidth: 28,
                rowHeight: 36,
                headerHeight: 52
            )
        }
        let pointOnC = CGPoint(x: rects[2].midX, y: rects[2].midY)

        XCTAssertFalse(rects[0].contains(pointOnC))
        XCTAssertFalse(rects[1].contains(pointOnC))
        XCTAssertTrue(rects[2].contains(pointOnC))
    }

    func testBarCapsAndCenterMapToIndependentDragModes() {
        let rect = GanttTimelineGeometry.barRect(
            startDay: 2,
            duration: 8,
            row: 1,
            dayWidth: 28,
            rowHeight: 36,
            headerHeight: 52
        )
        let regions = GanttTimelineGeometry.interactionRegions(for: rect, zoomScale: 1)

        XCTAssertEqual(
            GanttTimelineGeometry.dragMode(at: CGPoint(x: rect.minX, y: rect.midY), in: regions),
            .resizeStart
        )
        XCTAssertEqual(
            GanttTimelineGeometry.dragMode(at: CGPoint(x: rect.midX, y: rect.midY), in: regions),
            .move
        )
        XCTAssertEqual(
            GanttTimelineGeometry.dragMode(at: CGPoint(x: rect.maxX, y: rect.midY), in: regions),
            .resizeEnd
        )
    }
}
