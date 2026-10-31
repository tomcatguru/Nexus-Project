import Foundation

public enum GanttItemKind: String, Codable, CaseIterable, Sendable {
    case project
    case task
}

public struct GanttItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: GanttItemKind
    public var startDate: Date
    public var endDate: Date
    public var progress: Double
    public var parentID: UUID?
    public var dependencyIDs: [UUID]
    public var isExpanded: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        kind: GanttItemKind,
        startDate: Date,
        endDate: Date,
        progress: Double = 0,
        parentID: UUID? = nil,
        dependencyIDs: [UUID] = [],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.startDate = min(startDate, endDate)
        self.endDate = max(startDate, endDate)
        self.progress = min(max(progress, 0), 1)
        self.parentID = parentID
        self.dependencyIDs = dependencyIDs
        self.isExpanded = isExpanded
    }
}

public struct GanttDocument: Codable, Sendable {
    public var version: Int
    public var items: [GanttItem]

    public init(version: Int = 1, items: [GanttItem]) {
        self.version = version
        self.items = items
    }
}
