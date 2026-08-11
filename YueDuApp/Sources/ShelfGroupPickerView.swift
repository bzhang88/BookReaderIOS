import SwiftUI
import Persistence

/// Lets the user manually assign (or clear) one shelf book's group -- coexists with the "自动分组"
/// tag-rule sweep in `ShelfView` since both just write `ShelfBook.group`; picking a group here is
/// simply a manual override of whatever the last automatic sweep (if any) set.
struct ShelfGroupPickerView: View {
    let book: ShelfBook
    let existingGroups: [String]
    let onSelect: (String?) async -> Void

    @State private var newGroupName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("无分组") {
                        select(nil)
                    }
                }
                if !existingGroups.isEmpty {
                    Section("已有分组") {
                        ForEach(existingGroups, id: \.self) { group in
                            Button(group) {
                                select(group)
                            }
                        }
                    }
                }
                Section("新建分组") {
                    TextField("分组名称", text: $newGroupName)
                    Button("创建并使用") {
                        select(newGroupName)
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("设置分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func select(_ group: String?) {
        let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await onSelect(trimmed?.isEmpty == true ? nil : trimmed)
            dismiss()
        }
    }
}
