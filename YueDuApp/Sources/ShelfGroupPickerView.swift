import SwiftUI

/// Lets the user pick which group(s) one or more shelf books should belong to -- coexists with the
/// "自动分组" tag-rule sweep in `ShelfView` since both write `ShelfBook.groups`; picking here is a
/// manual override of whatever the last automatic sweep (if any) added. Not tied to a specific book
/// (there's nothing book-specific in this UI), so the same view serves both the single-row "改分组"
/// action and the multi-select "移动分组" batch action.
///
/// Real gap found comparing against Legado: `ShelfBook.groups` used to be a single optional
/// `String`, so a book could only ever be filed into one group at a time (Legado's own `Book.group`
/// is a bitmask precisely so a book can carry several groups' bits at once). This is now a checklist
/// -- tapping toggles membership, confirming applies the whole selected set at once.
struct ShelfGroupPickerView: View {
    let existingGroups: [String]
    /// Which groups should start checked -- the target book's(s') *current* groups for the
    /// single-row case, or empty for the batch case (there's no single "current set" across
    /// multiple, possibly differently-grouped, selected books).
    var initialGroups: [String] = []
    let onConfirm: ([String]) async -> Void

    @State private var selected: Set<String>
    @State private var newGroupName = ""
    @Environment(\.dismiss) private var dismiss

    init(existingGroups: [String], initialGroups: [String] = [], onConfirm: @escaping ([String]) async -> Void) {
        self.existingGroups = existingGroups
        self.initialGroups = initialGroups
        self.onConfirm = onConfirm
        _selected = State(initialValue: Set(initialGroups))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("清空所有分组") { selected = [] }
                        .disabled(selected.isEmpty)
                }
                if !existingGroups.isEmpty {
                    Section("已有分组") {
                        ForEach(existingGroups, id: \.self) { group in
                            groupRow(group)
                        }
                    }
                }
                Section("新建分组") {
                    HStack {
                        TextField("分组名称", text: $newGroupName)
                        Button("添加") { addNewGroup() }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("选择分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { confirm() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func groupRow(_ group: String) -> some View {
        Button {
            if selected.contains(group) {
                selected.remove(group)
            } else {
                selected.insert(group)
            }
        } label: {
            HStack {
                Text(group).foregroundStyle(.primary)
                Spacer()
                if selected.contains(group) {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func addNewGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selected.insert(trimmed)
        newGroupName = ""
    }

    private func confirm() {
        let result = Array(selected).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        Task {
            await onConfirm(result)
            dismiss()
        }
    }
}
