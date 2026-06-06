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
// MARK: – SpawnBox lifecycle spot
// ─────────────────────────────────────────────────────────────────────────────

private struct TrackedSpot {
    var center:    CGPoint
    var bounds:    CGRect
    var spawnTime: Date
    var deathTime: Date? = nil

    static let spawnDur: TimeInterval = 0.45
    static let deathDur: TimeInterval = 0.38

    var isExpired: Bool {
        guard let dt = deathTime else { return false }
        return Date().timeIntervalSince(dt) >= TrackedSpot.deathDur
    }

    mutating func revive() { deathTime = nil }

    func scale(at now: Date) -> CGFloat {
        if let dt = deathTime {
            let t = CGFloat(now.timeIntervalSince(dt) / TrackedSpot.deathDur)
            return max(0, 1.0 - t)                          // linear fade-out
        }
        let t = CGFloat(min(now.timeIntervalSince(spawnTime) / TrackedSpot.spawnDur, 1.0))
        let eased = 1.0 - pow(1.0 - t, 3)                  // ease-out cubic
        return max(0, eased)
    }

    // Smooth center/bounds toward a new detection. Suppresses jitter below threshold.
    mutating func move(toward cluster: TrackerCluster) {
        let t: CGFloat = 0.22
        let jitter: CGFloat = 0.004
        let dx = cluster.center.x - center.x
        let dy = cluster.center.y - center.y
        if abs(dx) > jitter || abs(dy) > jitter {
            center.x += dx * t
            center.y += dy * t
        }
        let b = cluster.bounds
        bounds = CGRect(
            x:      bounds.minX   + (b.minX   - bounds.minX)   * t,
            y:      bounds.minY   + (b.minY   - bounds.minY)   * t,
            width:  bounds.width  + (b.width  - bounds.width)  * t,
            height: bounds.height + (b.height - bounds.height) * t
        )
    }
}

private func computeUpdatedSpots(
    from newClusters: [TrackerCluster],
    current: [TrackedSpot]
) -> [TrackedSpot] {
    let now = Date()
    let matchThreshold: CGFloat = 0.28
    var updated = current.filter { !$0.isExpired }

    var matchedIndices = Set<Int>()
    var unmatched: [TrackerCluster] = []

    for cluster in newClusters {
        var bestIdx: Int? = nil
        var bestDist = matchThreshold
        // Match against ALL spots — including dying ones — so brief dropouts don't
        // spawn a second spot. A revived dying spot continues its existing animation.
        for (i, spot) in updated.enumerated() {
            let d = hypot(spot.center.x - cluster.center.x, spot.center.y - cluster.center.y)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        if let idx = bestIdx {
            matchedIndices.insert(idx)
            updated[idx].move(toward: cluster)
            updated[idx].revive()   // clear deathTime if it was dying
        } else {
            unmatched.append(cluster)
        }
    }

    for i in updated.indices where !matchedIndices.contains(i) && updated[i].deathTime == nil {
        updated[i].deathTime = now
    }

    for cluster in unmatched {
        updated.append(TrackedSpot(center: cluster.center, bounds: cluster.bounds, spawnTime: now))
    }

    return updated
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Tracker overlay
// ─────────────────────────────────────────────────────────────────────────────

struct TrackerOverlayView: View {
    let clusters:    [TrackerCluster]
    let trails:      [Int: [CGPoint]]
    let state:       AppState
    let contentRect: CGRect

    @State private var spots: [TrackedSpot] = []

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let isSpawn = state.boxStyle == .spawnBox
                guard (!clusters.isEmpty || (isSpawn && !spots.isEmpty)),
                      state.trackerEnabled else { return }

                let sw  = CGFloat(state.strokeWidth)
                let pad = CGFloat(state.boxPadding)

                func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                    CGPoint(
                        x: (contentRect.minX + nx * contentRect.width)  * size.width,
                        y: (contentRect.minY + ny * contentRect.height) * size.height
                    )
                }

                func boxRect(_ b: CGRect) -> CGRect {
                    let padded = b.insetBy(dx: -b.width * pad, dy: -b.height * pad)
                    let origin = pt(padded.minX, padded.minY)
                    let far    = pt(padded.maxX, padded.maxY)
                    return CGRect(x: origin.x, y: origin.y,
                                  width: far.x - origin.x, height: far.y - origin.y)
                }

                // ── Motion trails ─────────────────────────────────────────────
                if state.showMotionTrails {
                    for cl in clusters {
                        guard let trail = trails[cl.id], trail.count > 1 else { continue }
                        let trailSW = sw * 0.55
                        for i in 0..<(trail.count - 1) {
                            let alpha = Double(1.0 - Float(i) / Float(max(trail.count - 1, 1))) * 0.65
                            let thisSW = trailSW * CGFloat(1.0 - Float(i) / Float(trail.count) * 0.5)
                            var p = Path()
                            p.move(to: pt(trail[i].x, trail[i].y))
                            p.addLine(to: pt(trail[i + 1].x, trail[i + 1].y))
                            ctx.stroke(p, with: .color(state.boxColor.opacity(alpha)),
                                       style: StrokeStyle(lineWidth: thisSW, lineCap: .round))
                        }
                    }
                }

                // ── Connectors ────────────────────────────────────────────────
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
                        ctx.stroke(p, with: .color(state.boxColor.opacity(Double(state.connectorOpacity))),
                                   style: StrokeStyle(lineWidth: sw, dash: dash))
                    }
                }

                // ── Bounding boxes ────────────────────────────────────────────
                if state.showBoundingBoxes {
                    if isSpawn {
                        // SpawnBox: draw from lifecycle spots (includes dying ones)
                        let now = tl.date
                        for spot in spots {
                            let s = spot.scale(at: now)
                            guard s > 0.01 else { continue }
                            let alpha = Double(s * 0.9 + 0.1)
                            let cpt   = pt(spot.center.x, spot.center.y)
                            let r     = boxRect(spot.bounds)

                            // Scale corners outward from center
                            let sMinX = cpt.x + (r.minX - cpt.x) * s
                            let sMinY = cpt.y + (r.minY - cpt.y) * s
                            let sMaxX = cpt.x + (r.maxX - cpt.x) * s
                            let sMaxY = cpt.y + (r.maxY - cpt.y) * s
                            let sr    = CGRect(x: sMinX, y: sMinY,
                                               width: sMaxX - sMinX, height: sMaxY - sMinY)

                            // Corner brackets
                            let arm = min(sr.width, sr.height) * 0.25
                            if arm > 1 {
                                var p = Path()
                                func corner(_ x: CGFloat, _ y: CGFloat,
                                            _ dx: CGFloat, _ dy: CGFloat) {
                                    p.move(to: CGPoint(x: x, y: y + dy * arm))
                                    p.addLine(to: CGPoint(x: x, y: y))
                                    p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                                }
                                corner(sr.minX, sr.minY, +1, +1)
                                corner(sr.maxX, sr.minY, -1, +1)
                                corner(sr.maxX, sr.maxY, -1, -1)
                                corner(sr.minX, sr.maxY, +1, -1)
                                ctx.stroke(p, with: .color(state.boxColor.opacity(alpha)),
                                           style: StrokeStyle(lineWidth: sw, lineCap: .square))
                            }

                            // Fixed-size X at center — never scales
                            let xArm: CGFloat = 9.0
                            var xp = Path()
                            xp.move(to: CGPoint(x: cpt.x - xArm, y: cpt.y - xArm))
                            xp.addLine(to: CGPoint(x: cpt.x + xArm, y: cpt.y + xArm))
                            xp.move(to: CGPoint(x: cpt.x + xArm, y: cpt.y - xArm))
                            xp.addLine(to: CGPoint(x: cpt.x - xArm, y: cpt.y + xArm))
                            ctx.stroke(xp, with: .color(state.boxColor.opacity(alpha)),
                                       style: StrokeStyle(lineWidth: sw, lineCap: .round))
                        }
                    } else {
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
                                           with: .color(state.boxColor),
                                           style: StrokeStyle(lineWidth: sw))

                            case .cornerHUD:
                                if state.showFill {
                                    ctx.fill(RoundedRectangle(cornerRadius: cr).path(in: r),
                                             with: .color(fillShade))
                                }
                                let arm = min(r.width, r.height) * 0.22
                                var p = Path()
                                func corner(_ x: CGFloat, _ y: CGFloat,
                                            _ dx: CGFloat, _ dy: CGFloat) {
                                    p.move(to: CGPoint(x: x, y: y + dy * arm))
                                    p.addLine(to: CGPoint(x: x, y: y))
                                    p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                                }
                                corner(r.minX, r.minY, +1, +1); corner(r.maxX, r.minY, -1, +1)
                                corner(r.maxX, r.maxY, -1, -1); corner(r.minX, r.maxY, +1, -1)
                                ctx.stroke(p, with: .color(state.boxColor),
                                           style: StrokeStyle(lineWidth: sw, lineCap: .square))

                            case .filled:
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
                                ctx.stroke(p, with: .color(state.boxColor),
                                           style: StrokeStyle(lineWidth: sw, lineCap: .square))

                            case .reticle:
                                let cpt    = pt(cl.center.x, cl.center.y)
                                let radius = min(r.width, r.height) / 2
                                let tick   = max(radius * 0.38, 7.0)
                                let gap    = max(4.0, radius * 0.12)
                                var p = Path()
                                p.addEllipse(in: CGRect(x: cpt.x - radius, y: cpt.y - radius,
                                                        width: radius * 2, height: radius * 2))
                                p.move(to: CGPoint(x: cpt.x, y: cpt.y - radius - gap))
                                p.addLine(to: CGPoint(x: cpt.x, y: cpt.y - radius - gap - tick))
                                p.move(to: CGPoint(x: cpt.x, y: cpt.y + radius + gap))
                                p.addLine(to: CGPoint(x: cpt.x, y: cpt.y + radius + gap + tick))
                                p.move(to: CGPoint(x: cpt.x + radius + gap, y: cpt.y))
                                p.addLine(to: CGPoint(x: cpt.x + radius + gap + tick, y: cpt.y))
                                p.move(to: CGPoint(x: cpt.x - radius - gap, y: cpt.y))
                                p.addLine(to: CGPoint(x: cpt.x - radius - gap - tick, y: cpt.y))
                                ctx.stroke(p, with: .color(state.boxColor),
                                           style: StrokeStyle(lineWidth: sw, lineCap: .square))

                            case .spawnBox:
                                break  // handled above
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
                                        .foregroundStyle(state.boxColor),
                                    at: CGPoint(x: labelPt.x + 4, y: labelPt.y - 7)
                                )
                            }
                        }
                    }
                }

                // ── Center dots (skipped for spawnBox — X serves the same role)
                if state.showCenterDot && !isSpawn {
                    let dotR = CGFloat(state.centerDotSize) / 2
                    for cl in clusters {
                        let cpt = pt(cl.center.x, cl.center.y)
                        ctx.fill(Path(ellipseIn: CGRect(x: cpt.x - dotR, y: cpt.y - dotR,
                                                        width: dotR * 2, height: dotR * 2)),
                                 with: .color(state.boxColor))
                    }
                }
            }
        }
        .onChange(of: clusters) { _, newClusters in
            guard state.boxStyle == .spawnBox else { spots = []; return }
            spots = computeUpdatedSpots(from: newClusters, current: spots)
        }
        .onChange(of: state.boxStyle) { _, style in
            if style != .spawnBox { spots = [] }
        }
        .allowsHitTesting(false)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – ROI overlay (draggable region-of-interest box)
// ─────────────────────────────────────────────────────────────────────────────

struct ROIOverlayView: View {
    @Bindable var state: AppState
    let contentRect: CGRect

    private struct DragStart {
        let mode: DragMode
        let roi: (x: Float, y: Float, w: Float, h: Float)
    }

    private enum DragMode { case move, tl, tr, bl, br }

    @State private var dragStart: DragStart? = nil

    var body: some View {
        GeometryReader { geo in
            let cW = geo.size.width
            let cH = geo.size.height

            // Map normalized ROI to canvas coords
            let minX = (contentRect.minX + CGFloat(state.trackerROIX) * contentRect.width) * cW
            let minY = (contentRect.minY + CGFloat(state.trackerROIY) * contentRect.height) * cH
            let boxW = CGFloat(state.trackerROIW) * contentRect.width * cW
            let boxH = CGFloat(state.trackerROIH) * contentRect.height * cH
            let roiRect = CGRect(x: minX, y: minY, width: boxW, height: boxH)

            Canvas { ctx, _ in
                // Semi-transparent fill inside ROI
                ctx.fill(Path(roiRect), with: .color(Color.white.opacity(0.04)))

                // Dashed border
                ctx.stroke(Path(roiRect), with: .color(Color.white.opacity(0.62)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                // Darkened exterior mask — subtle, makes the ROI zone visually distinct
                var outside = Path(CGRect(x: 0, y: 0, width: cW, height: cH))
                outside.addRect(roiRect)  // even-odd fill cuts out the ROI interior
                ctx.fill(outside, with: .color(Color.black.opacity(0.28)))

                // Re-stroke the border on top
                ctx.stroke(Path(roiRect), with: .color(Color.white.opacity(0.62)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                // Corner handles (solid squares)
                let hs: CGFloat = 6
                for corner in [roiRect.origin,
                                CGPoint(x: roiRect.maxX, y: roiRect.minY),
                                CGPoint(x: roiRect.minX, y: roiRect.maxY),
                                CGPoint(x: roiRect.maxX, y: roiRect.maxY)] {
                    ctx.fill(
                        Path(CGRect(x: corner.x - hs, y: corner.y - hs, width: hs*2, height: hs*2)),
                        with: .color(Color.white.opacity(0.90))
                    )
                }

                // Center label
                if boxW > 80, boxH > 40 {
                    ctx.draw(
                        Text("TRACK ZONE")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.35)),
                        at: CGPoint(x: roiRect.midX, y: roiRect.midY)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStart == nil {
                            let mode = pickMode(at: value.startLocation, in: roiRect)
                            dragStart = DragStart(
                                mode: mode,
                                roi: (state.trackerROIX, state.trackerROIY,
                                      state.trackerROIW, state.trackerROIH)
                            )
                        }
                        guard let ds = dragStart else { return }
                        let dx = Float(value.translation.width  / (contentRect.width  * cW))
                        let dy = Float(value.translation.height / (contentRect.height * cH))
                        applyDrag(mode: ds.mode, base: ds.roi, dx: dx, dy: dy)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .allowsHitTesting(true)
    }

    private func pickMode(at point: CGPoint, in rect: CGRect) -> DragMode {
        let zone: CGFloat = 18
        if abs(point.x - rect.minX) < zone && abs(point.y - rect.minY) < zone { return .tl }
        if abs(point.x - rect.maxX) < zone && abs(point.y - rect.minY) < zone { return .tr }
        if abs(point.x - rect.minX) < zone && abs(point.y - rect.maxY) < zone { return .bl }
        if abs(point.x - rect.maxX) < zone && abs(point.y - rect.maxY) < zone { return .br }
        return .move
    }

    private func applyDrag(mode: DragMode,
                           base: (x: Float, y: Float, w: Float, h: Float),
                           dx: Float, dy: Float) {
        let minSz: Float = 0.05
        switch mode {
        case .move:
            state.trackerROIX = max(0, min(1 - base.w, base.x + dx))
            state.trackerROIY = max(0, min(1 - base.h, base.y + dy))

        case .tl:
            let nx = max(0, min(base.x + base.w - minSz, base.x + dx))
            let ny = max(0, min(base.y + base.h - minSz, base.y + dy))
            state.trackerROIX = nx; state.trackerROIY = ny
            state.trackerROIW = max(minSz, base.w - (nx - base.x))
            state.trackerROIH = max(minSz, base.h - (ny - base.y))

        case .tr:
            let ny = max(0, min(base.y + base.h - minSz, base.y + dy))
            state.trackerROIY = ny
            state.trackerROIH = max(minSz, base.h - (ny - base.y))
            state.trackerROIW = max(minSz, min(1 - base.x, base.w + dx))

        case .bl:
            let nx = max(0, min(base.x + base.w - minSz, base.x + dx))
            state.trackerROIX = nx
            state.trackerROIW = max(minSz, base.w - (nx - base.x))
            state.trackerROIH = max(minSz, min(1 - base.y, base.h + dy))

        case .br:
            state.trackerROIW = max(minSz, min(1 - base.x, base.w + dx))
            state.trackerROIH = max(minSz, min(1 - base.y, base.h + dy))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – HUD overlay
// ─────────────────────────────────────────────────────────────────────────────

struct HUDOverlayView: View {
    let clusters:    [TrackerCluster]
    let state:       AppState
    let contentRect: CGRect

    private let bearingFont  = Font.system(size: 9,  weight: .thin,        design: .default).monospacedDigit()
    private let compassFont  = Font.system(size: 7,  weight: .ultraLight,  design: .default)
    private let cardinalFont = Font.system(size: 8,  weight: .light,       design: .default)
    private let rangeFont    = Font.system(size: 8,  weight: .thin,        design: .default).monospacedDigit()
    private let crossFont    = Font.system(size: 7,  weight: .ultraLight,  design: .default).monospacedDigit()
    private let dataFont     = Font.system(size: 8,  weight: .ultraLight,  design: .default).monospacedDigit()
    private let nvFont       = Font.system(size: 7,  weight: .ultraLight,  design: .default)

    // Returns 0→1 progress through the 2-second init sequence; 1.0 = done (or never started)
    private func initProg(now: Double) -> Double {
        guard let it = state.hudInitTime else { return 1.0 }
        return min(max((now - it.timeIntervalSinceReferenceDate) / 2.0, 0), 1.0)
    }

    // Drives canvas opacity during boot: flicker-on then smooth ramp
    private func bootOpacity(now: Double) -> Double {
        guard let it = state.hudInitTime else { return 1.0 }
        let e = now - it.timeIntervalSinceReferenceDate
        if e <= 0    { return 0 }
        if e >  1.8  { return 1.0 }
        if e <  0.06 { return 0.85 }
        if e <  0.12 { return 0.10 }
        if e <  0.18 { return 0.75 }
        if e <  0.24 { return 0.10 }
        return (e - 0.24) / 1.56
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let now        = tl.date.timeIntervalSinceReferenceDate
            let tintColor: Color = state.hudNVMode
                ? Color(red: 0.22, green: 0.90, blue: 0.30)
                : state.hudTintColor
            let prog       = initProg(now: now)
            let canvasAlpha = bootOpacity(now: now)

            ZStack {
                Canvas { ctx, size in
                    guard state.hudEnabled else { return }

                    let sc   = CGFloat(state.hudScale)
                let bsw  = CGFloat(state.hudStrokeWidth)  // line thickness multiplier
                // Dynamic fonts — scale with hudTextScale so 4K output stays readable
                let ts   = CGFloat(state.hudTextScale)
                let compassFont  = Font.system(size: 7  * ts, weight: .ultraLight, design: .default)
                let cardinalFont = Font.system(size: 8  * ts, weight: .light,      design: .default)
                let bearingFont  = Font.system(size: 9  * ts, weight: .thin,       design: .default).monospacedDigit()
                let rangeFont    = Font.system(size: 8  * ts, weight: .thin,       design: .default).monospacedDigit()
                let crossFont    = Font.system(size: 7  * ts, weight: .ultraLight, design: .default).monospacedDigit()
                let dataFont     = Font.system(size: 8  * ts, weight: .ultraLight, design: .default).monospacedDigit()
                let nvFont       = Font.system(size: 7  * ts, weight: .ultraLight, design: .default)
                // NV mode overrides the tint to green
                let tint: Color = state.hudNVMode
                    ? Color(red: 0.22, green: 0.90, blue: 0.30)
                    : state.hudTintColor

                let rawMinX = contentRect.minX * size.width
                let rawMinY = contentRect.minY * size.height
                let rawMaxX = contentRect.maxX * size.width
                let rawMaxY = contentRect.maxY * size.height
                let rawW = rawMaxX - rawMinX
                let rawH = rawMaxY - rawMinY

                let mg    = CGFloat(state.hudMargin) * min(rawW, rawH)
                let fMinX = rawMinX + mg
                let fMinY = rawMinY + mg
                let fMaxX = rawMaxX - mg
                let fMaxY = rawMaxY - mg
                let fW    = fMaxX - fMinX
                let fH    = fMaxY - fMinY
                let fCX   = (fMinX + fMaxX) / 2
                let fCY   = (fMinY + fMaxY) / 2

                // ── Color tint ─────────────────────────────────────────────────
                if state.hudTintEnabled && state.hudTintOpacity > 0.005 {
                    ctx.fill(
                        Rectangle().path(in: CGRect(x: rawMinX, y: rawMinY, width: rawW, height: rawH)),
                        with: .color(tint.opacity(Double(state.hudTintOpacity)))
                    )
                }

                // ── Vignette ───────────────────────────────────────────────────
                if state.hudVignetteEnabled && !state.hudScopeFrame {
                    ctx.fill(
                        Rectangle().path(in: CGRect(x: rawMinX, y: rawMinY, width: rawW, height: rawH)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .clear, location: 0.40),
                                .init(color: .black.opacity(Double(state.hudVignetteStrength)), location: 1.0)
                            ]),
                            center: CGPoint(x: fCX, y: fCY),
                            startRadius: 0,
                            endRadius: max(rawW, rawH) * 0.68
                        )
                    )
                }

                // ── Scope frame — circular optic boundary ──────────────────────
                if state.hudScopeFrame {
                    let scopeR = min(rawW, rawH) * 0.5 * CGFloat(state.hudScopeRadius)
                    ctx.fill(
                        Rectangle().path(in: CGRect(x: rawMinX, y: rawMinY, width: rawW, height: rawH)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .clear,                                location: 0.84),
                                .init(color: .black.opacity(0.70),                  location: 0.90),
                                .init(color: .black.opacity(0.96),                  location: 0.97),
                                .init(color: .black,                                location: 1.00)
                            ]),
                            center: CGPoint(x: fCX, y: fCY),
                            startRadius: 0,
                            endRadius: scopeR
                        )
                    )
                    // Thin scope ring
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: fCX - scopeR * 0.885, y: fCY - scopeR * 0.885,
                                               width: scopeR * 0.885 * 2, height: scopeR * 0.885 * 2)),
                        with: .color(tint.opacity(0.22)),
                        style: StrokeStyle(lineWidth: 0.5)
                    )
                    // Vignette inside the scope
                    if state.hudVignetteEnabled {
                        ctx.fill(
                            Rectangle().path(in: CGRect(x: rawMinX, y: rawMinY, width: rawW, height: rawH)),
                            with: .radialGradient(
                                Gradient(stops: [
                                    .init(color: .clear, location: 0.35),
                                    .init(color: .black.opacity(Double(state.hudVignetteStrength) * 0.5), location: 0.84)
                                ]),
                                center: CGPoint(x: fCX, y: fCY),
                                startRadius: 0,
                                endRadius: scopeR * 0.88
                            )
                        )
                    }
                }

                // ── NV mode: enhanced atmospheric scan ─────────────────────────
                if state.hudNVMode {
                    let scanPhase = (now * 0.6).truncatingRemainder(dividingBy: 1.0)
                    let scanY = fMinY + CGFloat(scanPhase) * fH
                    var sl = Path()
                    sl.move(to: CGPoint(x: fMinX, y: scanY))
                    sl.addLine(to: CGPoint(x: fMaxX, y: scanY))
                    ctx.stroke(sl, with: .color(tint.opacity(0.10)), style: StrokeStyle(lineWidth: 0.5))
                    // GEN-3 badge (top-right)
                    ctx.draw(
                        Text("GEN-3").font(nvFont).foregroundStyle(tint.opacity(0.45)),
                        at: CGPoint(x: fMaxX - 8 * sc, y: fMinY + 8 * sc), anchor: .topTrailing
                    )
                }

                // ── Regular scan line ──────────────────────────────────────────
                if state.hudScanLineEnabled && !state.hudNVMode {
                    let phase = (now * Double(state.hudScanSpeed)).truncatingRemainder(dividingBy: 1.0)
                    let scanY = fMinY + CGFloat(phase) * fH
                    var sl = Path()
                    sl.move(to: CGPoint(x: fMinX, y: scanY)); sl.addLine(to: CGPoint(x: fMaxX, y: scanY))
                    ctx.stroke(sl, with: .color(tint.opacity(0.18)), style: StrokeStyle(lineWidth: 0.5))
                }

                // ── Tactical grid (bottom layer — very subtle dot matrix) ─────
                if state.hudTacticalGrid {
                    let gsp: CGFloat = min(fW, fH) * 0.07
                    let dotR: CGFloat = 0.8 * bsw
                    var gd = 0
                    var gy = fMinY + gsp / 2
                    while gy < fMaxY {
                        var gx = fMinX + gsp / 2
                        while gx < fMaxX {
                            let skip = abs(gx - fCX) < 12 * sc && abs(gy - fCY) < 12 * sc
                            if !skip {
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: gx-dotR, y: gy-dotR, width: dotR*2, height: dotR*2)),
                                    with: .color(tint.opacity(0.08))
                                )
                            }
                            gx += gsp; gd += 1
                        }
                        gy += gsp
                    }
                }

                // ── Range arcs (mid-field depth layers) ───────────────────────
                if state.hudRangeArcs {
                    let arcs: [(CGFloat, String, Double)] = [
                        (70, "100m", 0.16),
                        (110, "300m", 0.12),
                        (150, "500m", 0.09),
                    ]
                    for (r, label, alpha) in arcs {
                        let rSc = r * sc
                        guard rSc < min(fW, fH) * 0.52 else { continue }
                        // Four partial arcs at the diagonal quadrants
                        for startDeg: Double in [-135, -45, 45, 135] {
                            let start = startDeg * .pi / 180
                            let span  = 0.42 * .pi
                            var arc = Path()
                            arc.addArc(center: CGPoint(x: fCX, y: fCY), radius: rSc,
                                       startAngle: .radians(start), endAngle: .radians(start + span),
                                       clockwise: false)
                            ctx.stroke(arc, with: .color(tint.opacity(alpha)),
                                       style: StrokeStyle(lineWidth: 0.5 * bsw))
                        }
                        // Label at 3 o'clock
                        ctx.draw(Text(label).font(compassFont).foregroundStyle(tint.opacity(alpha + 0.05)),
                                 at: CGPoint(x: fCX + rSc + 3, y: fCY), anchor: .leading)
                    }
                }

                // ── Horizontal reference lines (extends into mid-field) ────────
                if state.hudHorizRef {
                    let refGap: CGFloat  = 32 * sc  // clear of crosshair
                    let refLen: CGFloat  = min(fW, fH) * 0.38
                    let tickH:  CGFloat  = 3 * sc
                    var hr = Path()
                    hr.move(to: CGPoint(x: fCX - refGap - refLen, y: fCY))
                    hr.addLine(to: CGPoint(x: fCX - refGap, y: fCY))
                    hr.move(to: CGPoint(x: fCX + refGap, y: fCY))
                    hr.addLine(to: CGPoint(x: fCX + refGap + refLen, y: fCY))
                    ctx.stroke(hr, with: .color(tint.opacity(0.22)), style: StrokeStyle(lineWidth: 0.4 * bsw))
                    // 3 ticks per side
                    for i in 1...3 {
                        let ox = refGap + CGFloat(i) * refLen / 3.5
                        let th = i % 2 == 0 ? tickH * 1.4 : tickH
                        var tick = Path()
                        tick.move(to: CGPoint(x: fCX - ox, y: fCY - th)); tick.addLine(to: CGPoint(x: fCX - ox, y: fCY + th))
                        tick.move(to: CGPoint(x: fCX + ox, y: fCY - th)); tick.addLine(to: CGPoint(x: fCX + ox, y: fCY + th))
                        ctx.stroke(tick, with: .color(tint.opacity(0.18)), style: StrokeStyle(lineWidth: 0.4 * bsw))
                    }
                }

                // ── Outer engagement box (user-requested, centered on frame) ───
                if state.hudOuterBox {
                    let half = min(fW, fH) * 0.5 * CGFloat(state.hudOuterBoxSize)
                    let arm  = half * 0.22
                    var ob = Path()
                    ob.move(to: CGPoint(x: fCX-half+arm, y: fCY-half)); ob.addLine(to: CGPoint(x: fCX-half, y: fCY-half)); ob.addLine(to: CGPoint(x: fCX-half, y: fCY-half+arm))
                    ob.move(to: CGPoint(x: fCX+half-arm, y: fCY-half)); ob.addLine(to: CGPoint(x: fCX+half, y: fCY-half)); ob.addLine(to: CGPoint(x: fCX+half, y: fCY-half+arm))
                    ob.move(to: CGPoint(x: fCX+half-arm, y: fCY+half)); ob.addLine(to: CGPoint(x: fCX+half, y: fCY+half)); ob.addLine(to: CGPoint(x: fCX+half, y: fCY+half-arm))
                    ob.move(to: CGPoint(x: fCX-half+arm, y: fCY+half)); ob.addLine(to: CGPoint(x: fCX-half, y: fCY+half)); ob.addLine(to: CGPoint(x: fCX-half, y: fCY+half-arm))
                    // Mid-edge ticks
                    let mt: CGFloat = 4 * sc
                    ob.move(to: CGPoint(x: fCX, y: fCY-half));      ob.addLine(to: CGPoint(x: fCX, y: fCY-half+mt))
                    ob.move(to: CGPoint(x: fCX, y: fCY+half));      ob.addLine(to: CGPoint(x: fCX, y: fCY+half-mt))
                    ob.move(to: CGPoint(x: fCX-half, y: fCY));      ob.addLine(to: CGPoint(x: fCX-half+mt, y: fCY))
                    ob.move(to: CGPoint(x: fCX+half, y: fCY));      ob.addLine(to: CGPoint(x: fCX+half-mt, y: fCY))
                    ctx.stroke(ob, with: .color(tint.opacity(0.42)), style: StrokeStyle(lineWidth: bsw * 0.85, lineCap: .square))
                }

                // ── Clock-position angle marks around reticle ─────────────────
                if state.hudAnglemarks {
                    let clockR: CGFloat = 44 * sc
                    for hour in 0..<12 {
                        let angle = CGFloat(hour) / 12.0 * .pi * 2 - .pi / 2
                        let isCard = hour % 3 == 0
                        let tLen: CGFloat = (isCard ? 5.5 : 3.0) * sc
                        let tipX = fCX + clockR * cos(angle)
                        let tipY = fCY + clockR * sin(angle)
                        let rootX = tipX - cos(angle) * tLen
                        let rootY = tipY - sin(angle) * tLen
                        var t = Path()
                        t.move(to: CGPoint(x: rootX, y: rootY))
                        t.addLine(to: CGPoint(x: tipX, y: tipY))
                        ctx.stroke(t, with: .color(tint.opacity(isCard ? 0.40 : 0.22)),
                                   style: StrokeStyle(lineWidth: 0.5 * bsw))
                    }
                }

                // ── Corner marks ───────────────────────────────────────────────
                if state.hudCornerFramesEnabled {
                    let arm = min(fW, fH) * 0.028 * sc
                    var cp = Path()
                    cp.move(to: CGPoint(x: fMinX + arm, y: fMinY)); cp.addLine(to: CGPoint(x: fMinX, y: fMinY)); cp.addLine(to: CGPoint(x: fMinX, y: fMinY + arm))
                    cp.move(to: CGPoint(x: fMaxX - arm, y: fMinY)); cp.addLine(to: CGPoint(x: fMaxX, y: fMinY)); cp.addLine(to: CGPoint(x: fMaxX, y: fMinY + arm))
                    cp.move(to: CGPoint(x: fMaxX - arm, y: fMaxY)); cp.addLine(to: CGPoint(x: fMaxX, y: fMaxY)); cp.addLine(to: CGPoint(x: fMaxX, y: fMaxY - arm))
                    cp.move(to: CGPoint(x: fMinX + arm, y: fMaxY)); cp.addLine(to: CGPoint(x: fMinX, y: fMaxY)); cp.addLine(to: CGPoint(x: fMinX, y: fMaxY - arm))
                    ctx.stroke(cp, with: .color(tint.opacity(0.45)), style: StrokeStyle(lineWidth: sc * 0.9, lineCap: .square))
                }

                // ── Pulse rings (drawn behind crosshair) ───────────────────────
                if state.hudPulseRings {
                    for i in 0..<3 {
                        let phase = ((now * 0.45) + Double(i) * 0.333).truncatingRemainder(dividingBy: 1.0)
                        let r = (16.0 + CGFloat(phase) * 58.0) * sc
                        let alpha = (1.0 - phase) * 0.26
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: fCX - r, y: fCY - r, width: r*2, height: r*2)),
                            with: .color(tint.opacity(alpha)),
                            style: StrokeStyle(lineWidth: 0.5)
                        )
                    }
                }

                // ── Crosshair + reticle system ─────────────────────────────────
                if state.hudCrosshairEnabled {
                    let armLen: CGFloat = 18 * sc
                    let gap:    CGFloat = 8  * sc
                    let sw:     CGFloat = 0.75 * bsw

                    // Stadia ranging circles (static — drawn before arms so arms sit on top)
                    if state.hudStadiaCircles {
                        let r1: CGFloat = 28 * sc
                        let r2: CGFloat = 52 * sc
                        ctx.stroke(Path(ellipseIn: CGRect(x: fCX-r1, y: fCY-r1, width: r1*2, height: r1*2)),
                                   with: .color(tint.opacity(0.22)), style: StrokeStyle(lineWidth: 0.5))
                        ctx.stroke(Path(ellipseIn: CGRect(x: fCX-r2, y: fCY-r2, width: r2*2, height: r2*2)),
                                   with: .color(tint.opacity(0.14)), style: StrokeStyle(lineWidth: 0.5))
                        // 3 o'clock label
                        ctx.draw(Text("1").font(compassFont).foregroundStyle(tint.opacity(0.22)),
                                 at: CGPoint(x: fCX+r1+2, y: fCY), anchor: .leading)
                        ctx.draw(Text("2").font(compassFont).foregroundStyle(tint.opacity(0.16)),
                                 at: CGPoint(x: fCX+r2+2, y: fCY), anchor: .leading)
                    }

                    // Arms
                    var xp = Path()
                    xp.move(to: CGPoint(x: fCX - armLen - gap, y: fCY)); xp.addLine(to: CGPoint(x: fCX - gap, y: fCY))
                    xp.move(to: CGPoint(x: fCX + gap, y: fCY));          xp.addLine(to: CGPoint(x: fCX + armLen + gap, y: fCY))
                    xp.move(to: CGPoint(x: fCX, y: fCY - armLen - gap)); xp.addLine(to: CGPoint(x: fCX, y: fCY - gap))
                    xp.move(to: CGPoint(x: fCX, y: fCY + gap));          xp.addLine(to: CGPoint(x: fCX, y: fCY + armLen + gap))
                    ctx.stroke(xp, with: .color(tint.opacity(0.72)), style: StrokeStyle(lineWidth: sw, lineCap: .butt))

                    // Mil-dots on all four arms
                    if state.hudMildots {
                        let spacing: CGFloat = 7 * sc
                        var dots = Path()
                        for mult: CGFloat in [1, 2, 3] {
                            let ox = gap + mult * spacing
                            guard ox < armLen + gap else { break }
                            let r: CGFloat = 1.0 * sc
                            dots.addEllipse(in: CGRect(x: fCX - ox - r, y: fCY - r, width: r*2, height: r*2))
                            dots.addEllipse(in: CGRect(x: fCX + ox - r, y: fCY - r, width: r*2, height: r*2))
                            dots.addEllipse(in: CGRect(x: fCX - r, y: fCY - ox - r, width: r*2, height: r*2))
                            dots.addEllipse(in: CGRect(x: fCX - r, y: fCY + ox - r, width: r*2, height: r*2))
                        }
                        ctx.fill(dots, with: .color(tint.opacity(0.52)))
                    }

                    // Windage correction dots — horizontal arm
                    if state.hudWindMarks {
                        let wSpacing: CGFloat = 10 * sc
                        var wdots = Path()
                        for mult: CGFloat in [1, 2] {
                            let ox = armLen * 0.35 + mult * wSpacing
                            let r: CGFloat = 1.2 * sc
                            wdots.addEllipse(in: CGRect(x: fCX - ox - r, y: fCY - r, width: r*2, height: r*2))
                            wdots.addEllipse(in: CGRect(x: fCX + ox - r, y: fCY - r, width: r*2, height: r*2))
                        }
                        ctx.fill(wdots, with: .color(tint.opacity(0.40)))
                    }

                    // Reticle ring + quarter ticks
                    if state.hudReticleRing {
                        let ringR = gap + 4 * sc
                        ctx.stroke(Path(ellipseIn: CGRect(x: fCX-ringR, y: fCY-ringR, width: ringR*2, height: ringR*2)),
                                   with: .color(tint.opacity(0.45)), style: StrokeStyle(lineWidth: sw * 0.8))
                        let tOut: CGFloat = 4 * sc
                        var qt = Path()
                        qt.move(to: CGPoint(x: fCX, y: fCY-ringR-tOut));     qt.addLine(to: CGPoint(x: fCX, y: fCY-ringR-1))
                        qt.move(to: CGPoint(x: fCX, y: fCY+ringR+1));        qt.addLine(to: CGPoint(x: fCX, y: fCY+ringR+tOut))
                        qt.move(to: CGPoint(x: fCX-ringR-tOut, y: fCY));     qt.addLine(to: CGPoint(x: fCX-ringR-1, y: fCY))
                        qt.move(to: CGPoint(x: fCX+ringR+1, y: fCY));        qt.addLine(to: CGPoint(x: fCX+ringR+tOut, y: fCY))
                        ctx.stroke(qt, with: .color(tint.opacity(0.42)), style: StrokeStyle(lineWidth: sw * 0.8, lineCap: .butt))
                    }

                    // BDC holdover marks below center
                    if state.hudBDCMarks {
                        let bdcStep: CGFloat = 11 * sc
                        let bdcRanges: [(Int, CGFloat)] = [(100,8),(200,6),(300,5),(400,4.5),(500,4)]
                        for (i, (rangeM, halfW)) in bdcRanges.enumerated() {
                            let markY = fCY + gap + bdcStep * CGFloat(i + 1)
                            guard markY < fMaxY - 10 else { break }
                            var mark = Path()
                            mark.move(to: CGPoint(x: fCX - halfW*sc, y: markY))
                            mark.addLine(to: CGPoint(x: fCX + halfW*sc, y: markY))
                            ctx.stroke(mark, with: .color(tint.opacity(0.52)), style: StrokeStyle(lineWidth: sw))
                            if i % 2 == 0 {
                                ctx.draw(Text("\(rangeM)").font(compassFont).foregroundStyle(tint.opacity(0.35)),
                                         at: CGPoint(x: fCX + halfW*sc + 4, y: markY), anchor: .leading)
                            }
                        }
                    }

                    // Elevation MOA marks — vertical arm ticks with labels
                    if state.hudElevMarks {
                        let moaStep: CGFloat = 6 * sc
                        for moa in [-3, -2, -1, 1, 2, 3] {
                            let y = fCY - CGFloat(moa) * moaStep
                            let halfW: CGFloat = abs(moa) % 2 == 0 ? 4.5 * sc : 2.5 * sc
                            var mark = Path()
                            mark.move(to: CGPoint(x: fCX - halfW, y: y))
                            mark.addLine(to: CGPoint(x: fCX + halfW, y: y))
                            ctx.stroke(mark, with: .color(tint.opacity(0.36)), style: StrokeStyle(lineWidth: 0.5))
                            if abs(moa) % 2 == 0 {
                                ctx.draw(
                                    Text(moa > 0 ? "+\(moa)" : "\(moa)").font(compassFont).foregroundStyle(tint.opacity(0.28)),
                                    at: CGPoint(x: fCX + halfW + 3, y: y), anchor: .leading
                                )
                            }
                        }
                    }

                    // ── Sweep arc (rotating radar-style scan) ──────────────────
                    if state.hudSweepArc {
                        let sweepAngle = CGFloat(now * 2.2).truncatingRemainder(dividingBy: .pi * 2)
                        let arcR: CGFloat = 38 * sc
                        let arcSpan: CGFloat = .pi * 0.28
                        let trailSpan: CGFloat = .pi * 0.55

                        // Trailing glow (faint, wide)
                        var trail = Path()
                        trail.addArc(center: CGPoint(x: fCX, y: fCY), radius: arcR,
                                     startAngle: .radians(Double(sweepAngle - trailSpan)),
                                     endAngle: .radians(Double(sweepAngle)), clockwise: false)
                        ctx.stroke(trail, with: .color(tint.opacity(0.11)),
                                   style: StrokeStyle(lineWidth: 1.8 * sc, lineCap: .round))

                        // Leading arc (bright)
                        var arc = Path()
                        arc.addArc(center: CGPoint(x: fCX, y: fCY), radius: arcR,
                                   startAngle: .radians(Double(sweepAngle)),
                                   endAngle: .radians(Double(sweepAngle + arcSpan)), clockwise: false)
                        ctx.stroke(arc, with: .color(tint.opacity(0.68)),
                                   style: StrokeStyle(lineWidth: 0.9 * sc, lineCap: .round))

                        // Bright dot at the leading tip
                        let tipX = fCX + arcR * cos(sweepAngle + arcSpan)
                        let tipY = fCY + arcR * sin(sweepAngle + arcSpan)
                        let tipR: CGFloat = 1.6 * sc
                        ctx.fill(Path(ellipseIn: CGRect(x: tipX-tipR, y: tipY-tipR, width: tipR*2, height: tipR*2)),
                                 with: .color(tint.opacity(0.88)))

                        // Second counter-rotating arc at a different radius (more complex look)
                        let sweepAngle2 = CGFloat(-now * 1.4).truncatingRemainder(dividingBy: .pi * 2)
                        let arcR2: CGFloat = 22 * sc
                        var arc2 = Path()
                        arc2.addArc(center: CGPoint(x: fCX, y: fCY), radius: arcR2,
                                    startAngle: .radians(Double(sweepAngle2)),
                                    endAngle: .radians(Double(sweepAngle2 + .pi * 0.20)), clockwise: false)
                        ctx.stroke(arc2, with: .color(tint.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 0.7 * sc, lineCap: .round))
                    }

                    // ── Breathing pause indicator ──────────────────────────────
                    if state.hudBreathPause {
                        let breathY = fCY + gap + armLen + 16 * sc
                        let breathW: CGFloat = 30 * sc
                        let cycleDur: Double = 4.8
                        let rawPhase = (now / cycleDur).truncatingRemainder(dividingBy: 1.0)
                        let isHold = rawPhase >= 0.78

                        // Track
                        var track = Path()
                        track.move(to: CGPoint(x: fCX - breathW, y: breathY))
                        track.addLine(to: CGPoint(x: fCX + breathW, y: breathY))
                        ctx.stroke(track, with: .color(tint.opacity(0.15)), style: StrokeStyle(lineWidth: 0.8))

                        // Optimal shot tick at center
                        var optTick = Path()
                        optTick.move(to: CGPoint(x: fCX, y: breathY - 2.5*sc))
                        optTick.addLine(to: CGPoint(x: fCX, y: breathY + 2.5*sc))
                        ctx.stroke(optTick, with: .color(tint.opacity(0.32)), style: StrokeStyle(lineWidth: 0.5))

                        // Inhale zone (left half) / exhale zone (right half) subtle labels
                        ctx.draw(Text("IN").font(compassFont).foregroundStyle(tint.opacity(0.18)),
                                 at: CGPoint(x: fCX - breathW, y: breathY - 4*sc), anchor: .bottomLeading)
                        ctx.draw(Text("OUT").font(compassFont).foregroundStyle(tint.opacity(0.18)),
                                 at: CGPoint(x: fCX + breathW, y: breathY - 4*sc), anchor: .bottomTrailing)

                        // Moving indicator
                        let cycleX: CGFloat
                        let indicAlpha: Double
                        if rawPhase < 0.40 {
                            cycleX = fCX - breathW + CGFloat(rawPhase / 0.40) * breathW
                            indicAlpha = 0.45
                        } else if rawPhase < 0.78 {
                            cycleX = fCX + CGFloat((rawPhase - 0.40) / 0.38) * breathW
                            indicAlpha = 0.60
                        } else {
                            cycleX = fCX + breathW * 0.88
                            indicAlpha = 0.92
                        }
                        let indR: CGFloat = 2.2 * sc
                        let indicColor: Color = isHold ? .white : tint
                        ctx.fill(Path(ellipseIn: CGRect(x: cycleX-indR, y: breathY-indR, width: indR*2, height: indR*2)),
                                 with: .color(indicColor.opacity(indicAlpha)))

                        if isHold {
                            ctx.draw(Text("HOLD").font(compassFont).foregroundStyle(tint.opacity(0.62)),
                                     at: CGPoint(x: fCX, y: breathY + 5*sc), anchor: .top)
                        }
                    }

                    // Near-crosshair range readout (nearest target)
                    if state.hudRangeCallouts && !clusters.isEmpty {
                        let nearest = clusters.min {
                            hypot($0.center.x - 0.5, $0.center.y - 0.5) < hypot($1.center.x - 0.5, $1.center.y - 0.5)
                        }
                        if let cl = nearest {
                            let area  = Double(cl.bounds.width * cl.bounds.height)
                            let distM = max(3, min(999, Int(0.015 / max(area, 1e-5) * 20)))
                            ctx.draw(
                                Text("\(distM)m").font(crossFont).foregroundStyle(tint.opacity(0.62)),
                                at: CGPoint(x: fCX + gap + 4*sc, y: fCY + gap + 4*sc), anchor: .topLeading
                            )
                        }
                    }
                }

                // ── Acquisition brackets (animated frames on detected targets) ──
                if state.hudAcquisitionBrackets && !clusters.isEmpty {
                    for cl in clusters {
                        let tx = (contentRect.minX + cl.center.x * contentRect.width)  * size.width
                        let ty = (contentRect.minY + cl.center.y * contentRect.height) * size.height

                        // Frame size from cluster bounds, with a minimum
                        let clW = max(28 * sc, cl.bounds.width  * rawW * CGFloat(contentRect.width)  + 16 * sc)
                        let clH = max(28 * sc, cl.bounds.height * rawH * CGFloat(contentRect.height) + 16 * sc)

                        // Subtle living pulse — brackets breathe slightly at different phases per target
                        let pulse  = 1.0 + 0.035 * sin(now * 3.8 + Double(cl.id) * 1.9)
                        let bW = clW * 0.5 * CGFloat(pulse)
                        let bH = clH * 0.5 * CGFloat(pulse)
                        let arm: CGFloat = min(bW, bH) * 0.35

                        var acq = Path()
                        acq.move(to: CGPoint(x: tx-bW+arm, y: ty-bH)); acq.addLine(to: CGPoint(x: tx-bW, y: ty-bH)); acq.addLine(to: CGPoint(x: tx-bW, y: ty-bH+arm))
                        acq.move(to: CGPoint(x: tx+bW-arm, y: ty-bH)); acq.addLine(to: CGPoint(x: tx+bW, y: ty-bH)); acq.addLine(to: CGPoint(x: tx+bW, y: ty-bH+arm))
                        acq.move(to: CGPoint(x: tx+bW-arm, y: ty+bH)); acq.addLine(to: CGPoint(x: tx+bW, y: ty+bH)); acq.addLine(to: CGPoint(x: tx+bW, y: ty+bH-arm))
                        acq.move(to: CGPoint(x: tx-bW+arm, y: ty+bH)); acq.addLine(to: CGPoint(x: tx-bW, y: ty+bH)); acq.addLine(to: CGPoint(x: tx-bW, y: ty+bH-arm))
                        ctx.stroke(acq, with: .color(tint.opacity(0.65)),
                                   style: StrokeStyle(lineWidth: 0.75, lineCap: .square))

                        // Confidence arc — fills around the bracket frame as confidence rises
                        let confAng = Double.pi * 2 * Double(cl.confidence)
                        let cr: CGFloat = min(bW, bH) * 0.72
                        var cArc = Path()
                        cArc.addArc(center: CGPoint(x: tx, y: ty), radius: cr,
                                    startAngle: .radians(-.pi / 2),
                                    endAngle: .radians(-.pi / 2 + confAng), clockwise: false)
                        ctx.stroke(cArc, with: .color(tint.opacity(0.30)),
                                   style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

                        // Small center cross at target centroid
                        let cLen: CGFloat = 3.5 * sc
                        var cc = Path()
                        cc.move(to: CGPoint(x: tx-cLen, y: ty)); cc.addLine(to: CGPoint(x: tx+cLen, y: ty))
                        cc.move(to: CGPoint(x: tx, y: ty-cLen)); cc.addLine(to: CGPoint(x: tx, y: ty+cLen))
                        ctx.stroke(cc, with: .color(tint.opacity(0.48)),
                                   style: StrokeStyle(lineWidth: 0.5, lineCap: .butt))
                    }
                }

                // ── Compass bar ────────────────────────────────────────────────
                if state.hudCompassEnabled {
                    let bearing   = (now * Double(state.hudCompassSpeed)).truncatingRemainder(dividingBy: 360.0)
                    let compassY  = fMinY + 18 * sc
                    let halfSpan: Double = 55
                    let pixPerDeg = Double(fW * 0.45) / halfSpan

                    var rule = Path()
                    rule.move(to: CGPoint(x: fMinX + fW * 0.1, y: compassY))
                    rule.addLine(to: CGPoint(x: fMaxX - fW * 0.1, y: compassY))
                    ctx.stroke(rule, with: .color(tint.opacity(0.20)), style: StrokeStyle(lineWidth: 0.5))

                    var d = 0
                    while d < 360 {
                        var offset = Double(d) - bearing
                        offset = ((offset + 540).truncatingRemainder(dividingBy: 360.0)) - 180.0
                        guard abs(offset) <= halfSpan + 5 else { d += 10; continue }
                        let x = fCX + CGFloat(offset * pixPerDeg)
                        guard x > fMinX + fW * 0.08, x < fMaxX - fW * 0.08 else { d += 10; continue }

                        let isCardinal = d % 90 == 0
                        let isThirty   = d % 30 == 0
                        let tickH = (isCardinal ? 7 : (isThirty ? 5 : 2.5)) * sc
                        let alpha: Double = isCardinal ? 0.70 : (isThirty ? 0.45 : 0.22)

                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: compassY - tickH)); tick.addLine(to: CGPoint(x: x, y: compassY))
                        ctx.stroke(tick, with: .color(tint.opacity(alpha)), style: StrokeStyle(lineWidth: 0.5))

                        if isCardinal {
                            let labels = [0:"N", 90:"E", 180:"S", 270:"W"]
                            if let lbl = labels[d] {
                                ctx.draw(Text(lbl).font(cardinalFont).foregroundStyle(tint.opacity(0.78)),
                                         at: CGPoint(x: x, y: compassY - tickH - 2 * sc), anchor: .bottom)
                            }
                        } else if isThirty {
                            ctx.draw(Text("\(d)").font(compassFont).foregroundStyle(tint.opacity(0.38)),
                                     at: CGPoint(x: x, y: compassY - tickH - 1), anchor: .bottom)
                        }
                        d += 10
                    }
                    let tri: CGFloat = 4 * sc
                    var marker = Path()
                    marker.move(to: CGPoint(x: fCX - tri, y: compassY - tri * 1.8))
                    marker.addLine(to: CGPoint(x: fCX + tri, y: compassY - tri * 1.8))
                    marker.addLine(to: CGPoint(x: fCX, y: compassY))
                    marker.closeSubpath()
                    ctx.fill(marker, with: .color(tint.opacity(0.82)))
                    let bearingInt = Int(bearing.truncatingRemainder(dividingBy: 360.0))
                    ctx.draw(Text(String(format: "%03d°", bearingInt)).font(bearingFont).foregroundStyle(tint.opacity(0.88)),
                             at: CGPoint(x: fCX, y: compassY - tri * 1.8 - 3), anchor: .bottom)
                }

                // ── Rangefinder callouts near each detected target ─────────────
                if state.hudRangeCallouts && !clusters.isEmpty {
                    for cl in clusters {
                        let sx  = (contentRect.minX + cl.center.x    * contentRect.width)  * size.width
                        let ty  = (contentRect.minY + cl.bounds.minY * contentRect.height) * size.height
                        let area  = Double(cl.bounds.width * cl.bounds.height)
                        let distM = max(3, min(999, Int(0.015 / max(area, 1e-5) * 20)))
                        let callY = ty - 6 * sc
                        var tl2 = Path()
                        tl2.move(to: CGPoint(x: sx - 9 * sc, y: callY)); tl2.addLine(to: CGPoint(x: sx + 9 * sc, y: callY))
                        ctx.stroke(tl2, with: .color(tint.opacity(0.50)), style: StrokeStyle(lineWidth: 0.5))
                        ctx.draw(Text("\(distM)m").font(rangeFont).foregroundStyle(tint.opacity(0.72)),
                                 at: CGPoint(x: sx, y: callY - 2), anchor: .bottom)
                    }
                }

                // ── Lateral scale bars (left + right mid-sides) ───────────────
                if state.hudLateralScale {
                    let scH: CGFloat = fH * 0.38
                    let scY = fCY - scH / 2
                    let numT = 10
                    let inset: CGFloat = 20 * sc

                    for side: CGFloat in [-1, 1] {
                        let scX = side < 0 ? fMinX + inset : fMaxX - inset
                        var bar = Path()
                        bar.move(to: CGPoint(x: scX, y: scY))
                        bar.addLine(to: CGPoint(x: scX, y: scY + scH))
                        for i in 0...numT {
                            let y = scY + CGFloat(i) / CGFloat(numT) * scH
                            let isMaj = i % 5 == 0
                            let tw: CGFloat = (isMaj ? 6 : 3) * sc * side
                            bar.move(to: CGPoint(x: scX, y: y))
                            bar.addLine(to: CGPoint(x: scX + tw, y: y))
                        }
                        ctx.stroke(bar, with: .color(tint.opacity(0.28)), style: StrokeStyle(lineWidth: 0.5 * bsw))
                        // Labels at top, mid, bottom
                        let labelOffX: CGFloat = side < 0 ? inset + 10 * sc : -(inset + 10 * sc)
                        let anchor: UnitPoint = side < 0 ? .leading : .trailing
                        for (lbl, frac) in [("+5", 0.0), ("0", 0.5), ("-5", 1.0)] {
                            ctx.draw(
                                Text(lbl).font(compassFont).foregroundStyle(tint.opacity(0.28)),
                                at: CGPoint(x: scX + labelOffX * 0.3, y: scY + CGFloat(frac) * scH), anchor: anchor
                            )
                        }
                    }
                }

                // ── IR signal bars (right mid-field) ──────────────────────────
                if state.hudSignalBars {
                    let barBaseX = fMaxX - 22 * sc
                    let barBaseY = fCY + 20 * sc
                    let barW: CGFloat = 3.5 * sc * bsw
                    let barMaxH: CGFloat = 22 * sc
                    let barGap: CGFloat  = 5.5 * sc
                    let numBars = 5

                    ctx.draw(Text("IR").font(nvFont).foregroundStyle(tint.opacity(0.30)),
                             at: CGPoint(x: barBaseX - CGFloat(numBars-1) * barGap * 0.5, y: barBaseY + 6*sc), anchor: .top)

                    for i in 0..<numBars {
                        let phase = sin(now * 0.38 + Double(i) * 0.72)
                        let h = barMaxH * CGFloat(0.28 + (phase + 1.0) * 0.36)
                        let alpha = 0.20 + (phase + 1.0) * 0.18
                        let bx = barBaseX - CGFloat(numBars - 1 - i) * barGap
                        var bar = Path()
                        bar.addRect(CGRect(x: bx - barW/2, y: barBaseY - h, width: barW, height: h))
                        ctx.fill(bar, with: .color(tint.opacity(alpha)))
                        // Top tick
                        var top = Path()
                        top.move(to: CGPoint(x: bx - barW/2, y: barBaseY - h))
                        top.addLine(to: CGPoint(x: bx + barW/2, y: barBaseY - h))
                        ctx.stroke(top, with: .color(tint.opacity(alpha + 0.12)), style: StrokeStyle(lineWidth: 0.5))
                    }
                }

                // ── Crosswind arrow (left mid-field) ──────────────────────────
                if state.hudCrosswindArrow {
                    let windSpeed = 2.5 + sin(now * 0.11) * 1.8
                    let windNorm  = sin(now * 0.07)          // -1…+1 (left/right)
                    let arrX = fMinX + fW * 0.16
                    let arrY = fCY + 30 * sc
                    let arrowLen: CGFloat = 30 * sc * CGFloat(abs(windNorm))
                    let dir: CGFloat = windNorm >= 0 ? 1 : -1

                    ctx.draw(Text("WIND").font(nvFont).foregroundStyle(tint.opacity(0.30)),
                             at: CGPoint(x: arrX, y: arrY - 7*sc), anchor: .bottomLeading)
                    ctx.draw(Text(String(format: "%.1f m/s", windSpeed)).font(compassFont).foregroundStyle(tint.opacity(0.42)),
                             at: CGPoint(x: arrX, y: arrY + 7*sc), anchor: .topLeading)

                    if arrowLen > 2 {
                        let tipX = arrX + dir * arrowLen
                        let hd: CGFloat = 5 * sc
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: arrX, y: arrY))
                        arrow.addLine(to: CGPoint(x: tipX, y: arrY))
                        arrow.move(to: CGPoint(x: tipX, y: arrY))
                        arrow.addLine(to: CGPoint(x: tipX - dir*hd, y: arrY - hd*0.55))
                        arrow.move(to: CGPoint(x: tipX, y: arrY))
                        arrow.addLine(to: CGPoint(x: tipX - dir*hd, y: arrY + hd*0.55))
                        ctx.stroke(arrow, with: .color(tint.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 0.75 * bsw, lineCap: .round))
                    } else {
                        // Calm — just a center dot
                        let cr: CGFloat = 2 * sc
                        ctx.fill(Path(ellipseIn: CGRect(x: arrX-cr, y: arrY-cr, width: cr*2, height: cr*2)),
                                 with: .color(tint.opacity(0.35)))
                    }
                }

                // ── Tactical data pane (bottom-left) ───────────────────────────
                if state.hudDataPane {
                    let cal = Calendar.current; let now2 = Date()
                    let hh  = cal.component(.hour,   from: now2)
                    let mm  = cal.component(.minute, from: now2)
                    let ss  = cal.component(.second, from: now2)
                    let timeStr = String(format: "%02d%02d", hh, mm)
                    let alt  = 612 + Int(sin(now * 0.008) * 4)
                    let temp = 14  + Int(sin(now * 0.005) * 2)
                    let gridE = 4827 + Int(now * 0.25) % 100
                    let gridN = 2193 + Int(now * 0.13) % 50
                    let elev  = 12  + Int(sin(now * 0.03) * 3)

                    let pad: CGFloat = 10 * sc
                    let lineH: CGFloat = 11 * sc
                    let x0 = fMinX + pad
                    let y0 = fMaxY - pad

                    let lines: [(String, Double)] = [
                        (timeStr + "L",                                 0.80),
                        (String(format: "ALT   %dm",    alt),           0.52),
                        (String(format: "TEMP  %+d°C",  temp),          0.45),
                        (String(format: "ELEV  +%d MIL", elev),         0.40),
                        (String(format: "MR %04d %04d", gridE, gridN),  0.35),
                    ]
                    for (i, (text, alpha)) in lines.enumerated() {
                        ctx.draw(
                            Text(text).font(dataFont).foregroundStyle(tint.opacity(alpha)),
                            at: CGPoint(x: x0, y: y0 - CGFloat(i) * lineH), anchor: .bottomLeading
                        )
                    }

                    // Vertical separator line beside the data block
                    var sep = Path()
                    sep.move(to:    CGPoint(x: x0 - 4, y: y0 + 2))
                    sep.addLine(to: CGPoint(x: x0 - 4, y: y0 - CGFloat(lines.count - 1) * lineH - 4))
                    ctx.stroke(sep, with: .color(tint.opacity(0.18)), style: StrokeStyle(lineWidth: 0.5))

                    // Top-right: elapsed time block
                    let elapsedSec = Int(now) % 3600
                    let eMin = elapsedSec / 60; let eSec = elapsedSec % 60
                    let elapsedStr = String(format: "%02d:%02d", eMin, eSec)
                    ctx.draw(
                        Text(elapsedStr).font(dataFont).foregroundStyle(tint.opacity(0.50)),
                        at: CGPoint(x: fMaxX - pad, y: fMaxY - pad), anchor: .bottomTrailing
                    )
                    ctx.draw(
                        Text(String(format: "%02d:%02d:%02d Z", hh, mm, ss)).font(nvFont).foregroundStyle(tint.opacity(0.30)),
                        at: CGPoint(x: fMaxX - pad, y: fMaxY - pad - lineH), anchor: .bottomTrailing
                    )
                }

                // ── Level / cant indicator (bottom center) ─────────────────────
                if state.hudLevelIndicator {
                    let levelY   = fMaxY - 10 * sc
                    let levelW: CGFloat = 36 * sc
                    let cant     = sin(now * 0.28) * 0.06   // subtle animated drift

                    // Track lines
                    var track = Path()
                    track.move(to: CGPoint(x: fCX - levelW, y: levelY))
                    track.addLine(to: CGPoint(x: fCX + levelW, y: levelY))
                    ctx.stroke(track, with: .color(tint.opacity(0.28)), style: StrokeStyle(lineWidth: 0.5))

                    // Center tick
                    var cMark = Path()
                    cMark.move(to: CGPoint(x: fCX, y: levelY - 3 * sc))
                    cMark.addLine(to: CGPoint(x: fCX, y: levelY + 3 * sc))
                    ctx.stroke(cMark, with: .color(tint.opacity(0.28)), style: StrokeStyle(lineWidth: 0.5))

                    // Bubble
                    let bubX = fCX + CGFloat(cant) * levelW * 8
                    let bR: CGFloat = 2.2 * sc
                    let bubbleColor: Color = abs(cant) < 0.01 ? tint : Color(red: 1, green: 0.6, blue: 0.1)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bubX - bR, y: levelY - bR, width: bR*2, height: bR*2)),
                        with: .color(bubbleColor.opacity(0.70))
                    )
                }

                // ── Range tick frame (secondary engagement bracket) ────────────
                if state.hudRangeTickFrame {
                    let half = min(fW, fH) * 0.5 * CGFloat(state.hudOuterBoxSize) * 0.55
                    let arm  = half * 0.14
                    var rtf = Path()
                    rtf.move(to: CGPoint(x: fCX-half+arm, y: fCY-half)); rtf.addLine(to: CGPoint(x: fCX-half, y: fCY-half)); rtf.addLine(to: CGPoint(x: fCX-half, y: fCY-half+arm))
                    rtf.move(to: CGPoint(x: fCX+half-arm, y: fCY-half)); rtf.addLine(to: CGPoint(x: fCX+half, y: fCY-half)); rtf.addLine(to: CGPoint(x: fCX+half, y: fCY-half+arm))
                    rtf.move(to: CGPoint(x: fCX+half-arm, y: fCY+half)); rtf.addLine(to: CGPoint(x: fCX+half, y: fCY+half)); rtf.addLine(to: CGPoint(x: fCX+half, y: fCY+half-arm))
                    rtf.move(to: CGPoint(x: fCX-half+arm, y: fCY+half)); rtf.addLine(to: CGPoint(x: fCX-half, y: fCY+half)); rtf.addLine(to: CGPoint(x: fCX-half, y: fCY+half-arm))
                    // Graduation ticks along each edge
                    for i in 1..<6 {
                        let t = CGFloat(i) / 6.0
                        let px = fCX - half + t * 2 * half
                        let py = fCY - half + t * 2 * half
                        let tw: CGFloat = i == 3 ? 5*sc : 2.5*sc
                        let tickAlpha: Double = i == 3 ? 0.38 : 0.22
                        var tk = Path()
                        tk.move(to: CGPoint(x: px, y: fCY-half));  tk.addLine(to: CGPoint(x: px, y: fCY-half+tw))
                        tk.move(to: CGPoint(x: px, y: fCY+half));  tk.addLine(to: CGPoint(x: px, y: fCY+half-tw))
                        tk.move(to: CGPoint(x: fCX-half, y: py));  tk.addLine(to: CGPoint(x: fCX-half+tw, y: py))
                        tk.move(to: CGPoint(x: fCX+half, y: py));  tk.addLine(to: CGPoint(x: fCX+half-tw, y: py))
                        ctx.stroke(tk, with: .color(tint.opacity(tickAlpha)), style: StrokeStyle(lineWidth: 0.4 * bsw))
                    }
                    ctx.stroke(rtf, with: .color(tint.opacity(0.30)), style: StrokeStyle(lineWidth: bsw * 0.6, lineCap: .square))
                }

                // ── Azimuth perimeter ring ─────────────────────────────────────
                if state.hudPerimeterRing {
                    let ringR: CGFloat = 72 * sc
                    ctx.stroke(Path(ellipseIn: CGRect(x: fCX-ringR, y: fCY-ringR, width: ringR*2, height: ringR*2)),
                               with: .color(tint.opacity(0.08)), style: StrokeStyle(lineWidth: 0.5 * bsw))
                    for i in 0..<24 {
                        let angle = CGFloat(i) / 24.0 * .pi * 2 - .pi / 2
                        let isMaj = i % 6 == 0
                        let isMed = i % 2 == 0
                        let tLen: CGFloat = isMaj ? 7*sc : (isMed ? 3.5*sc : 2.0*sc)
                        let alpha: Double  = isMaj ? 0.40 : (isMed ? 0.20 : 0.12)
                        let tipX = fCX + ringR * cos(angle)
                        let tipY = fCY + ringR * sin(angle)
                        var tt = Path()
                        tt.move(to: CGPoint(x: tipX, y: tipY))
                        tt.addLine(to: CGPoint(x: tipX - cos(angle)*tLen, y: tipY - sin(angle)*tLen))
                        ctx.stroke(tt, with: .color(tint.opacity(alpha)), style: StrokeStyle(lineWidth: 0.4 * bsw))
                        if isMaj {
                            let labels = [0:"N", 6:"E", 12:"S", 18:"W"]
                            if let lbl = labels[i] {
                                let lR = ringR - 10*sc
                                ctx.draw(Text(lbl).font(compassFont).foregroundStyle(tint.opacity(0.30)),
                                         at: CGPoint(x: fCX + lR*cos(angle), y: fCY + lR*sin(angle)), anchor: .center)
                            }
                        }
                    }
                }

                // ── Threat diamonds (4 diagonal positions) ─────────────────────
                if state.hudThreatDiamond {
                    let dR: CGFloat  = min(fW, fH) * 0.26 * sc
                    let dSz: CGFloat = 4.5 * sc
                    let pulse = 1.0 + 0.08 * sin(now * 1.4)
                    for qi in 0..<4 {
                        let angle = CGFloat(qi) * .pi / 2 + .pi / 4
                        let dx = fCX + dR * cos(angle)
                        let dy = fCY + dR * sin(angle)
                        let s  = dSz * CGFloat(pulse)
                        var diam = Path()
                        diam.move(to: CGPoint(x: dx, y: dy - s))
                        diam.addLine(to: CGPoint(x: dx + s, y: dy))
                        diam.addLine(to: CGPoint(x: dx, y: dy + s))
                        diam.addLine(to: CGPoint(x: dx - s, y: dy))
                        diam.closeSubpath()
                        ctx.stroke(diam, with: .color(tint.opacity(0.32)), style: StrokeStyle(lineWidth: 0.5 * bsw))
                        ctx.fill(Path(ellipseIn: CGRect(x: dx-1.2, y: dy-1.2, width: 2.4, height: 2.4)),
                                 with: .color(tint.opacity(0.22)))
                    }
                }

                // ── Lock arc (8-sector acquisition scan) ───────────────────────
                if state.hudLockArc {
                    let lockR: CGFloat = 58 * sc
                    let sectorDur: Double = 1.9
                    let tPhase  = (now / (sectorDur * 8)).truncatingRemainder(dividingBy: 1.0)
                    let sectIdx = Int(tPhase * 8)
                    let sectFrac = (tPhase * 8).truncatingRemainder(dividingBy: 1.0)
                    let holdAlpha = sectFrac < 0.68 ? 0.58 : max(0, (1.0 - sectFrac) / 0.32) * 0.58
                    let sectAngle = CGFloat(sectIdx) * .pi / 4 - .pi / 2

                    // Faint full ring
                    ctx.stroke(Path(ellipseIn: CGRect(x: fCX-lockR, y: fCY-lockR, width: lockR*2, height: lockR*2)),
                               with: .color(tint.opacity(0.06)), style: StrokeStyle(lineWidth: 0.4))

                    // 8 sector-boundary ticks
                    for s in 0..<8 {
                        let a = CGFloat(s) * .pi / 4 - .pi / 2
                        let x1 = fCX + (lockR - 4*sc) * cos(a)
                        let y1 = fCY + (lockR - 4*sc) * sin(a)
                        let x2 = fCX + (lockR + 4*sc) * cos(a)
                        let y2 = fCY + (lockR + 4*sc) * sin(a)
                        var tk = Path()
                        tk.move(to: CGPoint(x: x1, y: y1))
                        tk.addLine(to: CGPoint(x: x2, y: y2))
                        let active = s == sectIdx
                        ctx.stroke(tk, with: .color(tint.opacity(active ? 0.55 : 0.18)),
                                   style: StrokeStyle(lineWidth: active ? 0.7 : 0.4))
                    }

                    // Held sector arc
                    var lkArc = Path()
                    lkArc.addArc(center: CGPoint(x: fCX, y: fCY), radius: lockR,
                                 startAngle: .radians(Double(sectAngle)),
                                 endAngle: .radians(Double(sectAngle + .pi * 0.44)), clockwise: false)
                    ctx.stroke(lkArc, with: .color(tint.opacity(holdAlpha)),
                               style: StrokeStyle(lineWidth: 0.7 * bsw, lineCap: .round))

                    // Label on active sector
                    let midAngle = sectAngle + .pi * 0.22
                    let lR: CGFloat = lockR - 9*sc
                    ctx.draw(Text(["A","B","C","D","E","F","G","H"][sectIdx]).font(compassFont).foregroundStyle(tint.opacity(0.32)),
                             at: CGPoint(x: fCX + lR*cos(midAngle), y: fCY + lR*sin(midAngle)), anchor: .center)
                }

            }   // end Canvas
            .opacity(canvasAlpha)

            if prog < 0.96 && state.hudEnabled {
                hudBootView(progress: prog, tint: tintColor)
            }
        }   // end ZStack
    }   // end TimelineView
    .allowsHitTesting(false)
}

private func hudBootView(progress: Double, tint: Color) -> some View {
    let phase: String
    if progress < 0.30      { phase = "INITIALIZING" }
    else if progress < 0.60 { phase = "CALIBRATING"  }
    else if progress < 0.84 { phase = "ACQUIRING"     }
    else                    { phase = "READY"          }

    let alpha: Double = progress < 0.08 ? progress / 0.08
                      : progress > 0.88 ? max(0, (0.96 - progress) / 0.08) : 1.0

    return VStack(spacing: 5) {
        Text(phase)
            .font(.system(size: 9, weight: .thin, design: .monospaced))
            .tracking(3)
            .foregroundStyle(tint.opacity(0.65 * alpha))
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(0.12 * alpha))
                .frame(width: 96, height: 0.5)
            Rectangle()
                .fill(tint.opacity(0.44 * alpha))
                .frame(width: max(0, 96 * progress), height: 0.5)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
