import Foundation
import AppKit

@Observable
final class PresetManager {
    var userPresets: [Preset] = []
    var allPresets: [Preset] { Preset.builtins + userPresets }

    private let storageURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ASCIImp4/presets.json")
    }()

    init() { load() }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func save(_ preset: Preset) {
        if let idx = userPresets.firstIndex(where: { $0.id == preset.id }) {
            userPresets[idx] = preset
        } else {
            userPresets.append(preset)
        }
        persist()
    }

    func delete(_ preset: Preset) {
        userPresets.removeAll { $0.id == preset.id }
        persist()
    }

    // ── Import / Export ───────────────────────────────────────────────────────

    func exportPreset(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = preset.name
        panel.begin { [preset] result in
            guard result == .OK, let url = panel.url else { return }
            if let data = try? JSONEncoder().encode(preset) {
                try? data.write(to: url)
            }
        }
    }

    func importPreset(completion: @escaping (Preset?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            guard result == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  var preset = try? JSONDecoder().decode(Preset.self, from: data)
            else { completion(nil); return }
            preset.id       = UUID()
            preset.isBuiltin = false
            completion(preset)
        }
    }

    func exportAll() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ASCIImp4-presets"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            if let data = try? JSONEncoder().encode(self.userPresets) {
                try? data.write(to: url)
            }
        }
    }

    func importAll(completion: @escaping ([Preset]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            guard result == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let presets = try? JSONDecoder().decode([Preset].self, from: data)
            else { completion([]); return }
            completion(presets)
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private func persist() {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(userPresets) {
            try? data.write(to: storageURL)
        }
    }

    private func load() {
        guard
            let data    = try? Data(contentsOf: storageURL),
            let presets = try? JSONDecoder().decode([Preset].self, from: data)
        else { return }
        userPresets = presets.filter { !$0.isBuiltin }
    }
}
