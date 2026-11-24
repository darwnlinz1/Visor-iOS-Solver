// OpenVision - MemoriesView.swift
// AI memories management (key-value pairs, 100% Vietnamese UI).

import SwiftUI

private struct MemoryEditTarget: Identifiable {
    let id = UUID()
    let key: String?
    let value: String
}

struct MemoriesView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var editingTarget: MemoryEditTarget?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var memoryToDelete: String?

    var body: some View {
        List {
            if settingsManager.settings.memories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "brain")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text("Chưa có mục ghi nhớ nào")
                            .font(.headline)

                        Text("Thêm ngữ cảnh để trợ lý luôn nhớ về bạn (ví dụ: lớp học, môn thi, mục tiêu).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                Section {
                    ForEach(sortedMemoryKeys, id: \.self) { key in
                        Button {
                            editingTarget = MemoryEditTarget(
                                key: key,
                                value: settingsManager.settings.memories[key] ?? ""
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)

                                Text(settingsManager.settings.memories[key] ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                memoryToDelete = key
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Đã lưu")
                } footer: {
                    Text("\(settingsManager.settings.memories.count) mục ghi nhớ")
                }
            }
        }
        .navigationTitle("Ghi nhớ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTarget = MemoryEditTarget(key: nil, value: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Thêm ghi nhớ")
            }
        }
        .sheet(item: $editingTarget) { target in
            MemoryEditorView(
                existingKey: target.key,
                existingValue: target.value
            )
        }
        .confirmationDialog(
            "Xoá ghi nhớ",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) {
                if let key = memoryToDelete {
                    settingsManager.deleteMemory(key: key)
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            if let key = memoryToDelete {
                Text("Bạn có chắc muốn xoá '\(key)'?")
            }
        }
    }

    private var sortedMemoryKeys: [String] {
        settingsManager.settings.memories.keys.sorted()
    }
}

struct MemoryEditorView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    let existingKey: String?
    let existingValue: String

    @State private var key: String = ""
    @State private var value: String = ""
    @State private var showingDeleteConfirmation: Bool = false

    var isNewMemory: Bool { existingKey == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Khoá")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("lop_hoc", text: $key)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(!isNewMemory)
                    }
                } header: {
                    Text("Định danh")
                } footer: {
                    Text("Tên ngắn gọn (ví dụ: 'lop_hoc', 'mon_thi')")
                }

                Section {
                    TextEditor(text: $value)
                        .frame(minHeight: 100)
                } header: {
                    Text("Nội dung")
                } footer: {
                    Text("Thông tin muốn trợ lý luôn ghi nhớ")
                }

                if !isNewMemory {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Xoá ghi nhớ", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNewMemory ? "Ghi nhớ mới" : "Sửa ghi nhớ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveMemory()
                        dismiss()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                key = existingKey ?? ""
                value = existingValue
            }
            .confirmationDialog(
                "Xoá ghi nhớ",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Xoá", role: .destructive) {
                    if let existingKey {
                        settingsManager.deleteMemory(key: existingKey)
                    }
                    dismiss()
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Bạn có chắc muốn xoá ghi nhớ này?")
            }
        }
    }

    private func saveMemory() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingKey, existingKey != trimmedKey {
            settingsManager.renameMemory(oldKey: existingKey, newKey: trimmedKey)
        }

        settingsManager.setMemory(key: trimmedKey, value: trimmedValue)
        settingsManager.saveNow()
    }
}

#Preview {
    NavigationStack {
        MemoriesView()
            .environmentObject(SettingsManager.shared)
    }
    .preferredColorScheme(.dark)
}
