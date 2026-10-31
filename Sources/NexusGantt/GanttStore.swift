import Foundation
import SwiftUI
import NexusCore

enum GanttTimeScale: String, CaseIterable, Identifiable {
    case today
    case days
    case weeks
    case months
    case years

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .days: "Days"
        case .weeks: "Weeks"
        case .months: "Months"
        case .years: "Years"
        }
    }

    var dayWidth: CGFloat {
        switch self {
        case .today: 56
        case .days: 32
        case .weeks: 15
        case .months: 6
        case .years: 2.4
        }
    }
}

@MainActor
final class GanttStore: ObservableObject {
    @Published private(set) var items: [GanttItem] = []
    @Published var selectedID: UUID?
    @Published var timeScale: GanttTimeScale {
        didSet { defaults.set(timeScale.rawValue, forKey: Self.timeScaleKey) }
    }
    @Published var zoom: Double {
        didSet { defaults.set(zoom, forKey: Self.zoomKey) }
    }
    @Published private(set) var minimumZoom: Double = 0.65
    @Published var viewportOffset: CGPoint {
        didSet {
            defaults.set(viewportOffset.x, forKey: Self.offsetXKey)
            defaults.set(viewportOffset.y, forKey: Self.offsetYKey)
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let defaults: UserDefaults

    private static let zoomKey = "gantt.viewport.zoom"
    private static let timeScaleKey = "gantt.timeline.scale"
    private static let offsetXKey = "gantt.viewport.offset.x"
    private static let offsetYKey = "gantt.viewport.offset.y"

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timeScale = GanttTimeScale(
            rawValue: defaults.string(forKey: Self.timeScaleKey) ?? ""
        ) ?? .days
        let savedZoom = defaults.object(forKey: Self.zoomKey) as? Double ?? 1
        zoom = min(max(savedZoom, 0.65), 2)
        viewportOffset = CGPoint(
            x: defaults.double(forKey: Self.offsetXKey),
            y: defaults.double(forKey: Self.offsetYKey)
        )
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? base.appending(path: "NexusGantt", directoryHint: .isDirectory)
            .appending(path: "gantt.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func zoomIn() {
        zoom = min(2, (zoom + 0.1).rounded(toPlaces: 2))
    }

    func zoomOut() {
        zoom = max(minimumZoom, (zoom - 0.1).rounded(toPlaces: 2))
    }

    func resetZoom() {
        zoom = max(1, minimumZoom)
    }

    func resetViewport() {
        zoom = max(1, minimumZoom)
        viewportOffset = .zero
    }

    func selectTimeScale(_ newScale: GanttTimeScale) {
        let oldScale = timeScale
        timeScale = newScale
        zoom = 1

        let x: CGFloat
        if newScale == .today {
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: .now)
            let earliest = items.map(\.startDate).min() ?? today
            let rangeStart = calendar.startOfDay(for: earliest)
            let dayOffset = max(
                0,
                calendar.dateComponents([.day], from: rangeStart, to: today).day ?? 0
            )
            x = CGFloat(dayOffset) * newScale.dayWidth
        } else if oldScale != newScale {
            let visibleDay = viewportOffset.x / max(oldScale.dayWidth, 0.1)
            x = visibleDay * newScale.dayWidth
        } else {
            x = viewportOffset.x
        }

        viewportOffset = CGPoint(x: max(x, 0), y: viewportOffset.y)
    }

    func setMinimumZoom(_ value: Double) {
        let clamped = min(max(value, 0.65), 2)
        if abs(minimumZoom - clamped) > 0.001 {
            minimumZoom = clamped
        }
        if zoom < clamped {
            zoom = clamped
        }
    }

    var selectedItem: GanttItem? {
        items.first { $0.id == selectedID }
    }

    var activeProject: GanttItem? {
        guard var item = selectedItem ?? items.first(where: { $0.kind == .project }) else {
            return nil
        }

        var visited = Set<UUID>()
        while let parentID = item.parentID,
              visited.insert(parentID).inserted,
              let parent = self.item(parentID) {
            item = parent
        }
        return item.kind == .project ? item : items.first(where: { $0.kind == .project })
    }

    var visibleItems: [VisibleGanttItem] {
        GanttHierarchy.visibleItems(from: items)
    }

    func item(_ id: UUID) -> GanttItem? {
        items.first { $0.id == id }
    }

    func binding<Value>(
        for id: UUID,
        keyPath: WritableKeyPath<GanttItem, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { [weak self] in
                guard let item = self?.item(id) else { return fallback }
                return item[keyPath: keyPath]
            },
            set: { [weak self] value in
                self?.update(id) { $0[keyPath: keyPath] = value }
            }
        )
    }

    func addProject() {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 14, to: start)!
        let project = GanttItem(title: "새 프로젝트", kind: .project, startDate: start, endDate: end)
        items.append(project)
        selectedID = project.id
        save()
    }

    func addTask() {
        guard let parent = selectedItem ?? items.first(where: { $0.kind == .project }) else {
            addProject()
            return
        }
        let start = parent.startDate
        let proposedEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 4, to: start)!
        let task = GanttItem(
            title: "새 작업",
            kind: .task,
            startDate: start,
            endDate: min(proposedEnd, parent.endDate),
            parentID: parent.id,
            dependencyIDs: [parent.id]
        )
        items.append(task)
        update(parent.id) { $0.isExpanded = true }
        selectedID = task.id
        save()
    }

    func update(_ id: UUID, change: (inout GanttItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        if items[index].endDate < items[index].startDate {
            items[index].endDate = items[index].startDate
        }
        items[index].progress = min(max(items[index].progress, 0), 1)
        items = GanttHierarchy.sanitized(items)
        save()
    }

    func toggleExpanded(_ id: UUID) {
        update(id) { $0.isExpanded.toggle() }
    }

    func updateDates(for id: UUID, startDate: Date, endDate: Date) {
        update(id) {
            $0.startDate = startDate
            $0.endDate = endDate
        }
    }

    func setDependency(_ dependencyID: UUID?, for id: UUID) {
        update(id) { $0.dependencyIDs = dependencyID.map { [$0] } ?? [] }
    }

    @discardableResult
    func reparentTask(_ taskID: UUID, to newParentID: UUID) -> Bool {
        guard let updatedItems = GanttHierarchy.reparentingTask(
            taskID,
            to: newParentID,
            in: items
        ) else {
            return false
        }

        items = updatedItems
        selectedID = taskID
        save()
        return true
    }

    func allowedDependencies(for id: UUID) -> [GanttItem] {
        let allowed = Set(GanttHierarchy.ancestorIDs(of: id, in: items))
        return items.filter { allowed.contains($0.id) }
    }

    func deleteSelection() {
        guard let selectedID else { return }
        var pending = [selectedID]
        var deletion = Set<UUID>()
        while let next = pending.popLast(), deletion.insert(next).inserted {
            pending.append(contentsOf: items.filter { $0.parentID == next }.map(\.id))
        }

        var remainingItems = items.filter { !deletion.contains($0.id) }
        for index in remainingItems.indices {
            remainingItems[index].dependencyIDs.removeAll(where: deletion.contains)
        }

        // Clear the selection before publishing the new item collection. This
        // prevents InspectorView from reading a binding for a deleted item in
        // the transient render between the two @Published changes.
        self.selectedID = nil
        items = remainingItems
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            items = GanttHierarchy.sanitized(try decoder.decode(GanttDocument.self, from: data).items)
        } catch {
            items = Self.sampleItems()
        }
        selectedID = items.first?.id
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(GanttDocument(items: items)).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save Gantt document: \(error)")
        }
    }

    private static func sampleItems() -> [GanttItem] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

        let project = GanttItem(title: "Nexus 1.0", kind: .project, startDate: day(-3), endDate: day(25), progress: 0.28)
        let planning = GanttItem(title: "요구사항 및 설계", kind: .task, startDate: day(-3), endDate: day(3), progress: 0.85, parentID: project.id)
        let canvas = GanttItem(title: "Canvas 타임라인", kind: .task, startDate: day(2), endDate: day(12), progress: 0.4, parentID: project.id, dependencyIDs: [project.id])
        let interaction = GanttItem(title: "드래그 상호작용", kind: .task, startDate: day(7), endDate: day(17), progress: 0.1, parentID: canvas.id, dependencyIDs: [canvas.id])
        let release = GanttItem(title: "릴리스 준비", kind: .task, startDate: day(18), endDate: day(25), parentID: project.id, dependencyIDs: [project.id])
        return [project, planning, canvas, interaction, release]
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
