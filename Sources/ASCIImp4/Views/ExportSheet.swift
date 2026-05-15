import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Bindable var exportMgr: ExportManager
    let renderer:  CPURenderer
    let appState:  AppState
    let video:     VideoProcessor
    let bridge:    AEBridge
    @Binding var isPresented: Bool

    @State private var format:         ExportManager.Format     = .h264
    @State private var outputSizeMode: ExportManager.OutputSize = .source
    @State private var useSourceFPS  = true
    @State private var customFPS: Double = 30
    @State private var outputURL: URL? = nil

    private var effectiveFPS: Double { useSourceFPS ? max(video.fps, 24) : customFPS }
    private var hasVideo: Bool     { video.hasContent }
    private var hasSequence: Bool  { bridge.frameCount > 0 }
    private var canExportVideo: Bool { hasVideo || hasSequence }
    private var sourceLabel: String {
        if hasVideo     { return video.duration > 0 ? String(format: "Video  %.1fs @ %.0ffps", video.duration, video.fps) : "Video" }
        if hasSequence  { return "\(bridge.frameCount) frames @ \(Int(bridge.fps))fps" }
        return "Image"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Mono.border)

            if exportMgr.isExporting {
                exportingView
            } else {
                optionsView
            }
        }
        .frame(width: 360)
        .background(Mono.bg1)
        .preferredColorScheme(.dark)
    }

    // MARK: – Header

    private var header: some View {
        HStack {
            Text("Export")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Mono.text)
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Mono.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Mono.bg0)
    }

    // MARK: – Options

    private var optionsView: some View {
        VStack(spacing: 0) {
            // Source info
            HStack {
                Text("Source")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Mono.dim)
                Spacer()
                Text(sourceLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Mono.sub)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Mono.border.opacity(0.5))

            // PNG frame export (always available)
            Button {
                exportPNG()
            } label: {
                HStack {
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                        .foregroundStyle(Mono.dim)
                        .frame(width: 18)
                    Text("Save Current Frame as PNG")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Mono.text)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Mono.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if canExportVideo {
                Divider().background(Mono.border.opacity(0.5))

                // Video export section header
                HStack {
                    Text("Video Export")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Mono.dim)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

                // Format
                row(label: "Format") {
                    Picker("", selection: $format) {
                        ForEach(ExportManager.Format.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11, design: .monospaced))
                    .tint(Mono.sub)
                }

                // Resolution
                row(label: "Resolution") {
                    Picker("", selection: $outputSizeMode) {
                        ForEach(ExportManager.OutputSize.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11, design: .monospaced))
                    .tint(Mono.sub)
                }

                // FPS
                row(label: "Frame Rate") {
                    HStack(spacing: 8) {
                        Toggle("Source", isOn: $useSourceFPS)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Mono.sub)
                        if !useSourceFPS {
                            Picker("", selection: $customFPS) {
                                Text("24").tag(Double(24))
                                Text("30").tag(Double(30))
                                Text("60").tag(Double(60))
                            }
                            .pickerStyle(.menu)
                            .font(.system(size: 11, design: .monospaced))
                            .tint(Mono.sub)
                            .frame(width: 56)
                        }
                    }
                }

                if !format.supportsAlpha {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text("No alpha channel — use ProRes 4444 for transparency")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(.orange.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }

                if let errMsg = exportMgr.errorMessage {
                    Text(errMsg)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }

                Divider().background(Mono.border.opacity(0.5)).padding(.top, 8)

                Button {
                    chooseOutputAndExport()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "film")
                            .font(.system(size: 11))
                        Text("Export Video…")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Spacer()
                    }
                    .foregroundStyle(Mono.bg0)
                    .padding(.vertical, 10)
                    .background(Mono.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func row<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Mono.dim)
                .frame(width: 84, alignment: .leading)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: – Exporting progress

    private var exportingView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)

            Text("Rendering ASCII art…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Mono.sub)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Mono.bg3)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Mono.accent)
                            .frame(width: geo.size.width * exportMgr.progress, height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(Int(exportMgr.progress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Mono.dim)
            }
            .padding(.horizontal, 24)

            Button {
                exportMgr.cancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Mono.dim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Mono.bg3)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 16)
    }

    // MARK: – Actions

    private func exportPNG() {
        guard let img = renderer.renderCurrentFrameForExport(for: appState, transparent: true)
                     ?? renderer.lastFrame else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType.png]
        panel.nameFieldStringValue = "ascii-frame"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let rep  = NSBitmapImageRep(cgImage: img)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }

    private func chooseOutputAndExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [format == .h264 ? UTType.mpeg4Movie : UTType.quickTimeMovie]
        panel.nameFieldStringValue = "ascii-export"
        panel.begin { [format, outputSizeMode, effectiveFPS] result in
            guard result == .OK, let url = panel.url else { return }
            Task {
                if hasVideo, let srcURL = appState.sourceURL {
                    await exportMgr.exportVideo(
                        sourceURL:      srcURL,
                        renderer:       renderer,
                        appState:       appState,
                        format:         format,
                        outputSizeMode: outputSizeMode,
                        outputFPS:      effectiveFPS,
                        outputURL:      url
                    )
                } else if hasSequence {
                    await exportMgr.exportSequence(
                        framePaths:     bridge.framePaths,
                        renderer:       renderer,
                        appState:       appState,
                        format:         format,
                        outputSizeMode: outputSizeMode,
                        outputFPS:      effectiveFPS,
                        outputURL:      url
                    )
                }
            }
        }
    }
}
