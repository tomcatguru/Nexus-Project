import SwiftUI
import NexusCore

struct InspectorView: View {
    @EnvironmentObject private var store: GanttStore

    var body: some View {
        if let item = store.selectedItem {
            VStack(spacing: 0) {
                HStack {
                    Text("상세 정보")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(.bar)

                Divider()

                Form {
                    Section("기본 정보") {
                        TextField(
                            "이름",
                            text: store.binding(
                                for: item.id,
                                keyPath: \.title,
                                fallback: item.title
                            )
                        )
                        LabeledContent("종류", value: item.kind == .project ? "프로젝트" : "작업")
                    }

                    Section("일정") {
                        DatePicker(
                            "시작",
                            selection: store.binding(
                                for: item.id,
                                keyPath: \.startDate,
                                fallback: item.startDate
                            ),
                            displayedComponents: .date
                        )
                        DatePicker(
                            "종료",
                            selection: store.binding(
                                for: item.id,
                                keyPath: \.endDate,
                                fallback: item.endDate
                            ),
                            displayedComponents: .date
                        )
                        VStack(alignment: .leading) {
                            LabeledContent("진행률", value: "\(Int(item.progress * 100))%")
                            Slider(
                                value: store.binding(
                                    for: item.id,
                                    keyPath: \.progress,
                                    fallback: item.progress
                                ),
                                in: 0...1,
                                step: 0.05
                            )
                        }
                    }

                    if item.kind == .task {
                        Section("의존 관계") {
                            Picker("선행 항목", selection: dependencyBinding(for: item.id)) {
                                Text("없음").tag(UUID?.none)
                                ForEach(store.allowedDependencies(for: item.id)) { candidate in
                                    Text(candidate.title).tag(Optional(candidate.id))
                                }
                            }
                            Text("작업은 자신의 상위 작업 또는 프로젝트에만 의존할 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button("선택 항목 삭제", role: .destructive, action: store.deleteSelection)
                    }
                }
                .formStyle(.grouped)
            }
        } else {
            ContentUnavailableView("항목을 선택하세요", systemImage: "sidebar.right")
        }
    }

    private func dependencyBinding(for id: UUID) -> Binding<UUID?> {
        Binding(
            get: { store.item(id)?.dependencyIDs.first },
            set: { store.setDependency($0, for: id) }
        )
    }
}
