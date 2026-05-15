import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var appState    = AppState()
    @State private var presetMgr   = PresetManager()
    @State private var video       = VideoProcessor()
    @State private var bridge      = AEBridge()
    @State private var tracker     = TrackerProcessor()
    @State private var clusters:   [TrackerCluster] = []
    @State private var selectedTab: PanelTab = .render
    @State private var renderer      = CPURenderer()
    @State private var exportManager = ExportManager()
    @State private var showExport    = false
    @State private var isDragOver    = false
    @State private var lastCGImage: CGImage? = nil

    // Keeps already-visited panels alive so switching back is instant
    @State private var visitedTabs: Set<PanelTab> = [.render]

    var body: some View {
        HSplitView {

            // ── Left panel ────────────────────────────────────────────────────
            VStack(spacing: 0) {
                panelHeader
                Divider().background(Mono.border)
                TabSwitcher(selected: $selectedTab)
                    .onChange(of: selectedTab) { _, tab in visitedTabs.insert(tab) }

                // ZStack keeps all visited panels alive — no rebuild on switch
                ZStack(alignment: .top) {
                    panelContent(.render,   show: selectedTab == .render) {
                        RenderPanel(state: appState)
                    }
                    panelContent(.color,    show: selectedTab == .color) {
                        ColorPanel(state: appState)
                    }
                    panelContent(.tracker,  show: selectedTab == .tracker) {
                        TrackerPanel(state: appState)
                    }
                    panelContent(.presets,  show: selectedTab == .presets) {
                        PresetsPanel(state: appState, presetManager: presetMgr)
                    }
                }
                .frame(maxHeight: .infinity)

                aeBridgeBar
            }
            .frame(width: Mono.panelW)
            .background(Mono.bg1)

            // ── Preview + transport ───────────────────────────────────────────
            VStack(spacing: 0) {
                previewCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TransportBar(video: video, state: appState, bridge: bridge)
            }
        }
        .background(Mono.bg0)
        .preferredColorScheme(.dark)
        .onAppear { wireRenderer() }
        .onChange(of: appState.trackerEnabled) { _, on in on ? rerunTracker() : { clusters = [] }() }
        .onChange(of: appState.detectionMode) { _, _ in rerunTracker() }
        .onChange(of: appState.sensitivity)   { _, _ in rerunTracker() }
        .onChange(of: appState.maxClusters)   { _, _ in rerunTracker() }
        .onChange(of: appState.minArea)        { _, _ in rerunTracker() }
        .onChange(of: exportManager.isExporting) { _, exporting in
            // Auto-dismiss sheet when export finishes and no error
            if !exporting && exportManager.errorMessage == nil && showExport {
                // keep sheet open to show completion; user closes manually
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(exportMgr: exportManager, renderer: renderer, appState: appState,
                        video: video, bridge: bridge, isPresented: $showExport)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileRequest))   { _ in openFilePicker() }
        .onReceive(NotificationCenter.default.publisher(for: .exportFrameRequest)) { _ in showExport = true }
    }

    // Lazily renders a panel only after it has been visited for the first time
    @ViewBuilder
    private func panelContent<C: View>(_ tab: PanelTab, show: Bool, @ViewBuilder content: () -> C) -> some View {
        if visitedTabs.contains(tab) {
            content()
                .opacity(show ? 1 : 0)
                .allowsHitTesting(show)
        }
    }

    // ── Wire renderer ─────────────────────────────────────────────────────────

    private func wireRenderer() {
        renderer.appState = appState

        video.onFrame = { [renderer] pb in
            guard let cg = pb.toCGImage() else { return }
            renderer.updateSource(cg)
            runTracker(cgImage: cg)
        }
        bridge.onFrame = { [renderer] cg in
            renderer.updateSource(cg)
            runTracker(cgImage: cg)
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────

    private var panelHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Logo
                HStack(spacing: 0) {
                    Text("ASCII")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Mono.accent)
                    Text("mp4")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(Mono.dim)
                }

                Spacer()

                // AE indicator
                if appState.aeBridgeEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(bridge.isWatching
                                  ? Color(red: 0.25, green: 0.9, blue: 0.35)
                                  : Mono.dim)
                            .frame(width: 5, height: 5)
                        Text("AE")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Mono.dim)
                    }
                }

                if appState.hasSource {
                    MonoButton(label: "Export…", small: true) { showExport = true }
                }
                MonoButton(label: "Open", small: true) { openFilePicker() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Mono.bg0)
    }

    // ── AE Bridge bar ──────────────────────────────────────────────────────────

    private var aeBridgeBar: some View {
        VStack(spacing: 0) {
            Divider().background(Mono.border)
            HStack(spacing: 8) {
                Toggle("AE Bridge", isOn: $appState.aeBridgeEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7, anchor: .leading)
                    .tint(Mono.accent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Mono.dim)
                if appState.aeBridgeEnabled {
                    MonoButton(label: "Watch…", small: true) { bridge.chooseFolder() }
                    if bridge.isWatching {
                        MonoButton(label: "Export .jsx", small: true) {
                            if let f = bridge.watchFolder {
                                bridge.writeAEScript(to: f)
                                NSWorkspace.shared.open(f)
                            }
                        }
                    }
                }
                Spacer()
                if bridge.isWatching {
                    Text("\(bridge.frameCount)f")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Mono.dim)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(Mono.bg0)
        .onChange(of: appState.aeBridgeEnabled) { _, on in if !on { bridge.stopWatching() } }
    }

    // ── Preview canvas ─────────────────────────────────────────────────────────

    private var previewCanvas: some View {
        ZStack {
            ASCIIPreviewView(renderer: renderer)

            if !appState.hasSource {
                DropZoneOverlay()
            }
            if appState.trackerEnabled && !clusters.isEmpty {
                TrackerOverlayView(
                    clusters:    clusters,
                    state:       appState,
                    contentRect: renderer.contentRect
                )
            }
            if isDragOver {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Mono.accent.opacity(0.5), lineWidth: 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            guard let prov = providers.first else { return false }
            _ = prov.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL else { return }
                DispatchQueue.main.async { loadSource(url: url) }
            }
            return true
        }
    }

    // ── Source loading ─────────────────────────────────────────────────────────

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            loadSource(url: url)
        }
    }

    private func loadSource(url: URL) {
        let ext     = url.pathExtension.lowercased()
        let imgExts = Set(["png","jpg","jpeg","heic","tiff","tif","gif","bmp","webp","exr"])
        let vidExts = Set(["mp4","mov","m4v","avi","mkv","mxf"])

        if FileManager.default.directoryExists(at: url) {
            appState.isSequence = true; appState.isVideo = false; appState.isImage = false
            appState.sourceURL  = url
            bridge.startWatching(folder: url)
        } else if imgExts.contains(ext) {
            appState.isImage = true; appState.isVideo = false; appState.isSequence = false
            appState.sourceURL = url
            video.stop()
            loadImage(url: url)
        } else if vidExts.contains(ext) {
            appState.isVideo = true; appState.isImage = false; appState.isSequence = false
            appState.sourceURL = url
            video.load(url: url)
            video.play()
        }
    }

    private func loadImage(url: URL) {
        DispatchQueue.global(qos: .userInteractive).async {
            guard
                let src = NSImage(contentsOf: url),
                let rep = src.representations.first as? NSBitmapImageRep,
                let cg  = rep.cgImage
            else { return }
            DispatchQueue.main.async {
                renderer.updateSource(cg)
                runTracker(cgImage: cg)
            }
        }
    }

    // ── Tracker ───────────────────────────────────────────────────────────────

    private func runTracker(cgImage: CGImage) {
        lastCGImage = cgImage
        guard appState.trackerEnabled else { clusters = []; return }
        // Snapshot values on the main thread before crossing to the tracker's serial queue
        let input = TrackerProcessor.Input(
            cgImage:     cgImage,
            mode:        appState.detectionMode,
            maxClusters: appState.maxClusters,
            sensitivity: appState.sensitivity,
            minArea:     appState.minArea
        )
        tracker.detectAsync(input) { clusters = $0 }
    }

    private func rerunTracker() {
        guard appState.trackerEnabled, let cg = lastCGImage else { return }
        runTracker(cgImage: cg)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Notifications
// ─────────────────────────────────────────────────────────────────────────────

extension Notification.Name {
    static let openFileRequest   = Notification.Name("ASCIImp4.openFileRequest")
    static let exportFrameRequest = Notification.Name("ASCIImp4.exportFrameRequest")
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – FileManager helper
// ─────────────────────────────────────────────────────────────────────────────

extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
