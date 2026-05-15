import SwiftUI

struct PresetsPanel: View {
    @Bindable var state: AppState
    @Bindable var presetManager: PresetManager
    @State private var saveName: String = ""
    @State private var showSaveDialog = false
    @State private var searchText: String = ""

    var filtered: [Preset] {
        searchText.isEmpty ? presetManager.allPresets
            : presetManager.allPresets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Toolbar ───────────────────────────────────────────────────────
            HStack(spacing: 6) {
                MonoButton(label: "Save Current", small: true) {
                    saveName    = state.activePresetName ?? ""
                    showSaveDialog = true
                }
                MonoButton(label: "Import", small: true) {
                    presetManager.importPreset { preset in
                        guard let p = preset else { return }
                        presetManager.save(p)
                    }
                }
                MonoButton(label: "Export All", small: true) {
                    presetManager.exportAll()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // ── Search ────────────────────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Mono.dim)
                    .font(.system(size: 10))
                TextField("Search presets", text: $searchText)
                    .font(.system(size: 11, design: .monospaced))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Mono.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Mono.bg0)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Mono.border))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Rectangle().fill(Mono.border).frame(height: 1)

            // ── Builtin presets ───────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    let builtins = filtered.filter { $0.isBuiltin }
                    if !builtins.isEmpty {
                        SectionHeader("Built-in")
                        ForEach(builtins) { preset in
                            PresetRow(
                                preset: preset,
                                isActive: state.activePresetName == preset.name,
                                onApply: { state.apply(preset) },
                                onExport: { presetManager.exportPreset(preset) },
                                onDelete: nil
                            )
                        }
                    }

                    let user = filtered.filter { !$0.isBuiltin }
                    if !user.isEmpty {
                        SectionHeader("My Presets")
                        ForEach(user) { preset in
                            PresetRow(
                                preset: preset,
                                isActive: state.activePresetName == preset.name,
                                onApply: { state.apply(preset) },
                                onExport: { presetManager.exportPreset(preset) },
                                onDelete: { presetManager.delete(preset) }
                            )
                        }
                    }

                    if filtered.isEmpty {
                        Text("No presets found")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Mono.dim)
                            .padding(24)
                    }
                }
            }
        }
        .sheet(isPresented: $showSaveDialog) {
            SavePresetSheet(name: $saveName) { name in
                var snap      = state.snapshot()
                snap.name     = name
                snap.isBuiltin = false
                presetManager.save(snap)
                state.activePresetName = name
            }
        }
    }

    // ── Section header ────────────────────────────────────────────────────────

    private func SectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Mono.dim)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Mono.bg0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Preset row
// ─────────────────────────────────────────────────────────────────────────────

private struct PresetRow: View {
    let preset:   Preset
    let isActive: Bool
    let onApply:  () -> Void
    let onExport: () -> Void
    let onDelete: (() -> Void)?

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            if isActive {
                Circle()
                    .fill(Mono.accent)
                    .frame(width: 5, height: 5)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
            }

            Text(preset.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isActive ? Mono.accent : Mono.text)
                .lineLimit(1)

            Spacer()

            if hovered {
                HStack(spacing: 4) {
                    Button {
                        onExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                            .foregroundStyle(Mono.dim)
                    }
                    .buttonStyle(.plain)
                    .help("Export preset")

                    if let del = onDelete {
                        Button { del() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(Mono.dim)
                        }
                        .buttonStyle(.plain)
                        .help("Delete preset")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovered || isActive ? Mono.bg3 : Color.clear)
        .onHover { hovered = $0 }
        .onTapGesture { onApply() }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Save sheet
// ─────────────────────────────────────────────────────────────────────────────

private struct SavePresetSheet: View {
    @Binding var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Preset")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Mono.text)

            TextField("Preset name", text: $name)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(8)
                .background(Mono.bg0)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Mono.border))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onSubmit { save() }

            HStack(spacing: 10) {
                MonoButton(label: "Cancel") { dismiss() }
                MonoButton(label: "Save") { save() }
            }
        }
        .padding(24)
        .background(Mono.bg1)
        .frame(width: 260)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(name)
        dismiss()
    }
}
