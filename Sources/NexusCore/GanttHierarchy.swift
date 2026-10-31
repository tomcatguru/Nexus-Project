import Foundation

public struct VisibleGanttItem: Identifiable, Hashable, Sendable {
    public let item: GanttItem
    public let depth: Int
    public var id: UUID { item.id }

    public init(item: GanttItem, depth: Int) {
        self.item = item
        self.depth = depth
    }
}

public enum GanttHierarchy {
    public static func visibleItems(from items: [GanttItem]) -> [VisibleGanttItem] {
        let children = Dictionary(grouping: items, by: \.parentID)
        var result: [VisibleGanttItem] = []
        var visited = Set<UUID>()

        func markHiddenDescendants(of id: UUID) {
            for child in children[id] ?? [] where visited.insert(child.id).inserted {
                markHiddenDescendants(of: child.id)
            }
        }

        func append(_ item: GanttItem, depth: Int) {
            guard visited.insert(item.id).inserted else { return }
            result.append(VisibleGanttItem(item: item, depth: depth))
            guard item.isExpanded else {
                markHiddenDescendants(of: item.id)
                return
            }
            for child in (children[item.id] ?? []).sorted(by: itemOrder) {
                append(child, depth: depth + 1)
            }
        }

        for root in (children[nil] ?? []).sorted(by: itemOrder) {
            append(root, depth: 0)
        }

        // Keep malformed/orphaned records visible so they can be repaired in the UI.
        for item in items where !visited.contains(item.id) {
            append(item, depth: 0)
        }
        return result
    }

    public static func ancestorIDs(of id: UUID, in items: [GanttItem]) -> [UUID] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result: [UUID] = []
        var cursor = byID[id]?.parentID
        var visited = Set<UUID>()
        while let current = cursor, visited.insert(current).inserted {
            result.append(current)
            cursor = byID[current]?.parentID
        }
        return result
    }

    /// Moves a task beneath another task or project. Projects are fixed roots,
    /// and a task cannot be moved beneath itself or one of its descendants.
    public static func reparentingTask(
        _ taskID: UUID,
        to newParentID: UUID,
        in items: [GanttItem]
    ) -> [GanttItem]? {
        guard taskID != newParentID,
              let taskIndex = items.firstIndex(where: { $0.id == taskID }),
              items[taskIndex].kind == .task,
              items.contains(where: { $0.id == newParentID }),
              items[taskIndex].parentID != newParentID,
              !ancestorIDs(of: newParentID, in: items).contains(taskID) else {
            return nil
        }

        var result = items
        result[taskIndex].parentID = newParentID
        result[taskIndex].dependencyIDs = [newParentID]

        if let parentIndex = result.firstIndex(where: { $0.id == newParentID }) {
            result[parentIndex].isExpanded = true
        }

        return sanitized(result)
    }

    public static func sanitized(_ items: [GanttItem]) -> [GanttItem] {
        let ids = Set(items.map(\.id))
        return items.map { original in
            var item = original
            item.progress = min(max(item.progress, 0), 1)
            if item.endDate < item.startDate { item.endDate = item.startDate }
            if let parentID = item.parentID, !ids.contains(parentID) || parentID == item.id {
                item.parentID = nil
            }
            let allowed = Set(ancestorIDs(of: item.id, in: items))
            item.dependencyIDs = Array(Set(item.dependencyIDs)).filter(allowed.contains)
            return item
        }
    }

    private static func itemOrder(_ lhs: GanttItem, _ rhs: GanttItem) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
