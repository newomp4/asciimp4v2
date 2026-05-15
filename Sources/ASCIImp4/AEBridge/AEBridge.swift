import Foundation
import AppKit

// AE Bridge — watches a folder for PNG sequences exported from After Effects.
// The companion AE ExtendScript (aeExport.jsx) is written next to the app and
// exports Roto/Pre-comp frames as numbered PNGs with alpha straight into the folder.

@Observable
final class AEBridge {

    var isWatching:  Bool = false
    var watchFolder: URL? = nil
    var frameCount:  Int  = 0
    var currentFrame: Int = 0
    var framePaths:  [URL] = []
    var fps:         Double = 24

    var onFrame: ((CGImage) -> Void)?
    var onSequenceLoaded: (([URL]) -> Void)?

    private var pollTimer: Timer?
    private var playTimer: Timer?
    private var isPlaying: Bool = false
    private var knownFiles: Set<String> = []

    // ── Watch folder ──────────────────────────────────────────────────────────

    func startWatching(folder: URL) {
        stopWatching()
        watchFolder = folder
        isWatching  = true
        knownFiles  = []
        scanFolder()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.scanFolder()
        }
    }

    func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
        isWatching = false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles       = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.startWatching(folder: url)
        }
    }

    // ── Playback ──────────────────────────────────────────────────────────────

    func play() {
        guard !framePaths.isEmpty else { return }
        isPlaying   = true
        currentFrame = 0
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.nextFrame()
        }
    }

    func stop() {
        playTimer?.invalidate()
        playTimer  = nil
        isPlaying  = false
        currentFrame = 0
    }

    func seekTo(frame: Int) {
        currentFrame = max(0, min(frame, framePaths.count - 1))
        loadFrame(at: currentFrame)
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    private func scanFolder() {
        guard let folder = watchFolder else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.nameKey],
            options: .skipsHiddenFiles
        ) else { return }

        let pngs = items
            .filter { ["png","exr","tiff","tif"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let names = Set(pngs.map(\.lastPathComponent))
        let hasNew = !names.isSubset(of: knownFiles)

        if hasNew {
            knownFiles  = names
            framePaths  = pngs
            frameCount  = pngs.count
            onSequenceLoaded?(pngs)
            if !isPlaying { loadFrame(at: currentFrame) }
        }
    }

    private func nextFrame() {
        guard !framePaths.isEmpty else { return }
        loadFrame(at: currentFrame)
        currentFrame = (currentFrame + 1) % framePaths.count
    }

    private func loadFrame(at index: Int) {
        guard index < framePaths.count else { return }
        let url = framePaths[index]
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard
                let self,
                let src = NSImage(contentsOf: url),
                let rep = src.representations.first as? NSBitmapImageRep,
                let cg  = rep.cgImage
            else { return }
            DispatchQueue.main.async { self.onFrame?(cg) }
        }
    }

    // ── Export companion AE script ────────────────────────────────────────────

    func writeAEScript(to folder: URL) {
        let script = """
// ASCIImp4 — AE Export Script
// Drop this file into After Effects via File > Scripts > Run Script File
// It exports the active comp's Roto/masked layer as a PNG sequence with alpha
// into the specified output folder.

var outputFolder = new Folder("\(folder.path)");
if (!outputFolder.exists) outputFolder.create();

var comp = app.project.activeItem;
if (!(comp instanceof CompItem)) {
    alert("Please make a composition active first.");
} else {
    var renderQueue = app.project.renderQueue;
    var rqItem = renderQueue.items.add(comp);

    var om = rqItem.outputModule(1);
    om.applyTemplate("_HIDDEN");
    om.file = new File(outputFolder.fsName + "/frame_[####].png");

    var fmtOpts = om.getSettings(GetSettingsFormat.STRING);
    om.format = "PNG";
    om.channels = ChannelType.RGBA;

    rqItem.render();
    alert("Export complete!\\nFrames saved to: " + outputFolder.fsName);
}
"""
        let url = folder.appendingPathComponent("aeExport.jsx")
        try? script.write(to: url, atomically: true, encoding: .utf8)
    }
}
