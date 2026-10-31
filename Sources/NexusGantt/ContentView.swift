import SwiftUI
import NexusCore

struct ContentView: View {
    @EnvironmentObject private var store: GanttStore
    @State private var selectedSection: ProjectSection = .tasks

    var body: some View {
        VStack(spacing: 0) {
            ProjectHeader()
            ProjectTabBar(selection: $selectedSection)

            Divider()

            if selectedSection == .tasks {
                TimelineControlBar()
                Divider()

                HSplitView {
                    GanttBoard()
                        .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

                    InspectorView()
                        .frame(minWidth: 270, idealWidth: 300, maxWidth: 380, maxHeight: .infinity)
                }
            } else {
                ProjectSectionPlaceholder(section: selectedSection)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.addProject() } label: {
                    Label("프로젝트 추가", systemImage: "folder.badge.plus")
                }
                Button { store.addTask() } label: {
                    Label("작업 추가", systemImage: "plus")
                }
                Divider()
                Button { store.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("축소 (⌘−)")
                .disabled(store.zoom <= store.minimumZoom + 0.001)
                Text("\(Int(store.zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 38)
                Button { store.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("확대 (⌘+)")
            }
        }
    }
}

private enum ProjectSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tasks = "Task"
    case milestones = "Milestones"
    case files = "Files"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .tasks: "list.bullet.rectangle"
        case .milestones: "flag.checkered"
        case .files: "folder"
        }
    }
}

private struct ProjectHeader: View {
    @EnvironmentObject private var store: GanttStore
    @State private var editingProjectID: UUID?

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                if let project = store.activeProject {
                    if editingProjectID == project.id {
                        ProjectNameEditor(
                            text: project.title,
                            onCommit: { commitRename(project.id, title: $0) },
                            onCancel: { editingProjectID = nil }
                        )
                        .frame(width: 300, height: 26)
                    } else {
                        Text(project.title)
                            .font(.title2.bold())
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                editingProjectID = project.id
                            }
                            .help("더블 클릭하여 프로젝트 이름 변경")
                    }
                } else {
                    Text("Nexus Gantt")
                        .font(.title2.bold())
                }

                Text("Project workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("Active")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.green.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func commitRename(_ projectID: UUID, title proposedTitle: String) {
        guard editingProjectID == projectID else { return }
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            store.update(projectID) { $0.title = title }
        }
        editingProjectID = nil
    }
}

private struct ProjectTabBar: View {
    @Binding var selection: ProjectSection

    var body: some View {
        HStack(spacing: 28) {
            ForEach(ProjectSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.symbol)
                        Text(section.rawValue)
                    }
                    .font(.subheadline.weight(selection == section ? .semibold : .regular))
                    .foregroundStyle(selection == section ? Color.accentColor : Color.secondary)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if selection == section {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

private struct TimelineControlBar: View {
    @EnvironmentObject private var store: GanttStore

    var body: some View {
        ZStack {
            HStack {
                Spacer()

                Button {
                    store.resetViewport()
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                Label("Timeline", systemImage: "calendar.day.timeline.left")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 2) {
                    ForEach(GanttTimeScale.allCases) { scale in
                        Button {
                            store.selectTimeScale(scale)
                        } label: {
                            HStack(spacing: 5) {
                                if scale == .today {
                                    Image(systemName: "scope")
                                }
                                Text(scale.title)
                            }
                            .font(.caption.weight(store.timeScale == scale ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(store.timeScale == scale ? Color.primary : Color.secondary)
                            .background(
                                store.timeScale == scale
                                    ? Color(nsColor: .controlBackgroundColor)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ProjectSectionPlaceholder: View {
    let section: ProjectSection

    var body: some View {
        ContentUnavailableView(
            "\(section.rawValue) 준비 중",
            systemImage: section.symbol,
            description: Text("현재 초기 버전에서는 Task 간트 차트를 사용할 수 있습니다.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
