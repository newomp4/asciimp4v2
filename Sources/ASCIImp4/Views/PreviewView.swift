import SwiftUI
import CoreVideo
import CoreImage
import AppKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – NSViewRepresentable wrapping ASCIIDisplayView
// ─────────────────────────────────────────────────────────────────────────────

struct ASCIIPreviewView: NSViewRepresentable {
    let renderer: CPURenderer

    func makeNSView(context: Context) -> ASCIIDisplayView {
        let view = ASCIIDisplayView()
        renderer.displayView = view
        return view
    }

    func updateNSView(_ nsView: ASCIIDisplayView, context: Context) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Tracker overlay
// ─────────────────────────────────────────────────────────────────────────────

struct TrackerOverlayView: View {
    let clusters:    [TrackerCluster]
    let state:       AppState
    let contentRect: CGRect  // normalized (0-1) region where ASCII content is drawn

    var body: some View {
        Canvas { ctx, size in
            guard !clusters.isEmpty, state.trackerEnabled else { return }
            let sw = CGFloat(state.strokeWidth)
            let pad = CGFloat(state.boxPadding)

            // Map normalized source coord → canvas point (accounts for letterbox/pillarbox).
            func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                CGPoint(
                    x: (contentRect.minX + nx * contentRect.width)  * size.width,
                    y: (contentRect.minY + ny * contentRect.height) * size.height
                )
            }
            // Convert normalized cluster bounds → canvas rect, applying box padding.
            func boxRect(_ b: CGRect) -> CGRect {
                let padded = b.insetBy(dx: -b.width * pad, dy: -b.height * pad)
                let origin = pt(padded.minX, padded.minY)
                let far    = pt(padded.maxX, padded.maxY)
                return CGRect(x: origin.x, y: origin.y,
                              width: far.x - origin.x, height: far.y - origin.y)
            }

            if state.showConnectors && clusters.count > 1 {
                let dash: [CGFloat] = {
                    switch state.connectorStyle {
                    case .solid:  return []
                    case .dashed: return [8, 5]
                    case .dotted: return [2, 4]
                    }
                }()
                for i in 0..<(clusters.count - 1) {
                    let a = clusters[i], b = clusters[i + 1]
                    var p = Path()
                    p.move(to:    pt(a.center.x, a.center.y))
                    p.addLine(to: pt(b.center.x, b.center.y))
                    ctx.stroke(p, with: .color(.white.opacity(Double(state.connectorOpacity))),
                               style: StrokeStyle(lineWidth: sw, dash: dash))
                }
            }

            if state.showBoundingBoxes {
                let fillShade = state.fillColor.opacity(Double(state.fillOpacity))
                for cl in clusters {
                    let r  = boxRect(cl.bounds)
                    let cr: CGFloat = state.roundedCorners ? 6 : 0

                    switch state.boxStyle {
                    case .rect:
                        if state.showFill {
                            ctx.fill(RoundedRectangle(cornerRadius: cr).path(in: r),
                                     with: .color(fillShade))
                        }
                        ctx.stroke(RoundedRectangle(cornerRadius: cr).path(in: r),
                                   with: .color(.white), style: StrokeStyle(lineWidth: sw))

                    case .cornerHUD:
                        if state.showFill {
                            ctx.fill(RoundedRectangle(cornerRadius: cr).path(in: r),
                                     with: .color(fillShade))
                        }
                        let arm = min(r.width, r.height) * 0.22
                        var p = Path()
                        func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                            p.move(to: CGPoint(x: x, y: y + dy * arm))
                            p.addLine(to: CGPoint(x: x, y: y))
                            p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                        }
                        corner(r.minX, r.minY, +1, +1); corner(r.maxX, r.minY, -1, +1)
                        corner(r.maxX, r.maxY, -1, -1); corner(r.minX, r.maxY, +1, -1)
                        ctx.stroke(p, with: .color(.white),
                                   style: StrokeStyle(lineWidth: sw, lineCap: .square))

                    case .filled:
                        // Fill-only: no stroke border, just the soft block
                        ctx.fill(RoundedRectangle(cornerRadius: max(cr, 4)).path(in: r),
                                 with: .color(state.fillColor.opacity(Double(state.fillOpacity))))

                    case .crosshair:
                        if state.showFill {
                            ctx.fill(RoundedRectangle(cornerRadius: cr).path(in: r),
                                     with: .color(fillShade))
                        }
                        let cpt  = pt(cl.center.x, cl.center.y)
                        let armW = r.width  * 0.55
                        let armH = r.height * 0.55
                        var p = Path()
                        p.move(to: CGPoint(x: cpt.x - armW, y: cpt.y))
                        p.addLine(to: CGPoint(x: cpt.x + armW, y: cpt.y))
                        p.move(to: CGPoint(x: cpt.x, y: cpt.y - armH))
                        p.addLine(to: CGPoint(x: cpt.x, y: cpt.y + armH))
                        ctx.stroke(p, with: .color(.white),
                                   style: StrokeStyle(lineWidth: sw, lineCap: .square))
                    }

                    if state.showLabels {
                        let label: String = {
                            switch state.labelContent {
                            case .id:          return "[\(cl.id)]"
                            case .coordinates: return String(format: "%.2f,%.2f", cl.center.x, cl.center.y)
                            case .area:        return String(format: "%.0fpx²", cl.area)
                            case .confidence:  return String(format: "%.0f%%", cl.confidence * 100)
                            }
                        }()
                        let labelPt = pt(cl.bounds.minX, cl.bounds.minY)
                        ctx.draw(
                            Text(label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white),
                            at: CGPoint(x: labelPt.x + 4, y: labelPt.y - 7)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Transport bar
// ─────────────────────────────────────────────────────────────────────────────

struct TransportBar: View {
    @Bindable var video:  VideoProcessor
    @Bindable var state:  AppState
    @Bindable var bridge: AEBridge

    @State private var isScrubbing = false
    @State private var playBtnHovered = false
    @State private var loopBtnHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Play / Pause
            Button { video.togglePlayPause() } label: {
                Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(playBtnHovered ? Mono.accent : Mono.text)
                    .frame(width: 26, height: 26)
                    .background(playBtnHovered ? Mono.bg3 : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!video.hasContent && bridge.frameCount == 0)
            .onHover { playBtnHovered = $0 }

            if video.hasContent {
                Slider(
                    value: Binding(
                        get: { video.currentTime },
                        set: { t in
                            video.currentTime = t
                            if isScrubbing { video.scrub(to: t) }
                            else           { video.seek(to: t) }
                        }
                    ),
                    in: 0...max(video.duration, 0.001),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { video.seek(to: video.currentTime) }
                    }
                )
                .tint(Mono.accent)

                Text(formatTime(video.currentTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Mono.dim)
                    .frame(width: 50, alignment: .trailing)
                    .monospacedDigit()

            } else if bridge.frameCount > 0 {
                Slider(value: Binding(
                    get: { Double(bridge.currentFrame) },
                    set: { bridge.seekTo(frame: Int($0)) }
                ), in: 0...Double(max(bridge.frameCount - 1, 1)))
                .tint(Mono.accent)

                Text("\(bridge.currentFrame + 1)/\(bridge.frameCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Mono.dim)
                    .frame(width: 56, alignment: .trailing)
                    .monospacedDigit()

            } else {
                Capsule()
                    .fill(Mono.bg2.opacity(0.6))
                    .frame(height: 3)
            }

            // Loop
            Button { video.isLooping.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        video.isLooping
                            ? (loopBtnHovered ? Mono.accent.opacity(0.7) : Mono.accent)
                            : (loopBtnHovered ? Mono.text : Mono.dim)
                    )
                    .frame(width: 26, height: 26)
                    .background(loopBtnHovered ? Mono.bg3 : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Loop playback")
            .onHover { loopBtnHovered = $0 }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Mono.bg0)
        .overlay(Rectangle().fill(Mono.muted.opacity(0.7)).frame(height: 1), alignment: .top)
    }

    private func formatTime(_ t: Double) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// DropZoneOverlay lives in Components.swift

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – AppState convenience
// ─────────────────────────────────────────────────────────────────────────────

extension AppState {
    var hasSource: Bool { isImage || isVideo || isSequence }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – CVPixelBuffer → CGImage
// ─────────────────────────────────────────────────────────────────────────────

extension CVPixelBuffer {
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    func toCGImage() -> CGImage? {
        let ci = CIImage(cvPixelBuffer: self)
        return CVPixelBuffer.sharedCIContext.createCGImage(ci, from: ci.extent)
    }
}
