import Foundation
import CoreText
import CoreGraphics
import AppKit
import QuartzCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Display view  (CALayer-backed, updated without SwiftUI overhead)
// ─────────────────────────────────────────────────────────────────────────────

final class ASCIIDisplayView: NSView {

    var cgImage: CGImage? {
        didSet { layer?.contents = cgImage }
    }

    override var wantsLayer: Bool { get { true } set {} }

    override func makeBackingLayer() -> CALayer {
        let l = CALayer()
        l.contentsGravity    = .resizeAspect
        l.backgroundColor    = .clear
        l.needsDisplayOnBoundsChange = true
        return l
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – CPU Renderer
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class CPURenderer {

    weak var appState:    AppState?
    weak var displayView: ASCIIDisplayView?

    // Normalized rect (0-1 relative to view size) of where content is drawn.
    // Used by TrackerOverlayView to align cluster boxes with letterboxed content.
    var contentRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    // Last rendered frame — used for PNG export
    var lastFrame: CGImage? = nil

    private var sourceImage: CGImage?
    private var displayLink: CVDisplayLink?
    private let renderLock  = DispatchSemaphore(value: 1)

    // Cached font state
    private var cgFont:       CGFont?
    private var ctFont:       CTFont?
    private var glyphs:       [CGGlyph] = []
    private var lastCellSize: Int = 0
    private var lastCharSet:  CharacterSetType = .standard
    private var lastCustom:   String = ""

    init() { startDisplayLink() }
    deinit { stopDisplayLink() }

    // ── Source ─────────────────────────────────────────────────────────────────

    func updateSource(_ image: CGImage?) {
        sourceImage = image
    }

    // Synchronous render for offline export — bypasses the display link.
    // transparent=true skips the background fill (use for ProRes 4444 / PNG).
    // viewportSize is the live preview size; cell size is scaled to match preview density.
    func renderOffline(
        _ cgImage: CGImage,
        size: CGSize,
        for state: AppState,
        transparent: Bool = false,
        viewportSize: CGSize = .zero,
        clusters: [TrackerCluster] = []
    ) -> (CGImage?, CGRect) {
        let cellScale = viewportSize.width > 0 ? Double(size.width) / Double(viewportSize.width) : 1.0
        if abs(cellScale - 1.0) <= 0.01 { rebuildFontIfNeeded(state: state) }
        return render(source: cgImage, outputSize: size, state: state,
                      transparent: transparent, cellScale: cellScale, clusters: clusters)
    }

    func renderTrackerFrame(
        _ cgImage: CGImage,
        size: CGSize,
        for state: AppState,
        viewportSize: CGSize,
        clusters: [TrackerCluster]
    ) -> CGImage? {
        let outW = Int(size.width), outH = Int(size.height)
        let cellScale = viewportSize.width > 0 ? Double(size.width) / Double(viewportSize.width) : 1.0
        let cellW = max(1, Int(Double(state.cellSize) * cellScale))
        let cellH = max(1, Int(Double(state.cellHeight) * cellScale))

        let srcAspect  = Double(cgImage.width) / Double(cgImage.height)
        let viewAspect = size.width / size.height
        let renderW: Int; let renderH: Int; let offsetX: Int; let offsetY: Int
        if srcAspect > viewAspect {
            renderW = outW; renderH = max(Int(Double(outW) / srcAspect), cellH)
            offsetX = 0;    offsetY = (outH - renderH) / 2
        } else {
            renderH = outH; renderW = max(Int(Double(outH) * srcAspect), cellW)
            offsetX = (outW - renderW) / 2; offsetY = 0
        }
        let cRect = CGRect(
            x: CGFloat(offsetX) / CGFloat(outW), y: CGFloat(offsetY) / CGFloat(outH),
            width: CGFloat(renderW) / CGFloat(outW), height: CGFloat(renderH) / CGFloat(outH)
        )

        let bmi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8,
                                  bytesPerRow: outW * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bmi)
        else { return nil }

        CPURenderer.drawTracker(clusters: clusters, contentRect: cRect, state: state,
                                ctx: ctx, outW: outW, outH: outH, scale: cellScale)
        return ctx.makeImage()
    }

    func renderCurrentFrameForExport(for state: AppState, transparent: Bool) -> CGImage? {
        guard let src = sourceImage else { return nil }
        rebuildFontIfNeeded(state: state)
        let size = displayView?.bounds.size ?? CGSize(width: 1920, height: 1080)
        return render(source: src, outputSize: size, state: state, transparent: transparent).0
    }

    // ── Display link ───────────────────────────────────────────────────────────

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, raw -> CVReturn in
            let renderer = Unmanaged<CPURenderer>.fromOpaque(raw!).takeUnretainedValue()
            guard renderer.renderLock.wait(timeout: .now()) == .success else {
                return kCVReturnSuccess
            }
            DispatchQueue.global(qos: .userInteractive).async { renderer.tick() }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
        displayLink = nil
    }

    private func tick() {
        defer { renderLock.signal() }

        guard
            let state  = appState,
            let source = sourceImage,
            let view   = displayView
        else { return }

        let size = view.bounds.size
        guard size.width > 4, size.height > 4 else { return }

        rebuildFontIfNeeded(state: state)

        let (img, cRect) = render(source: source, outputSize: size, state: state, transparent: true)
        DispatchQueue.main.async { [weak view, weak self] in
            view?.cgImage = img
            self?.lastFrame   = img
            self?.contentRect = cRect
        }
    }

    // ── Font / glyph cache ─────────────────────────────────────────────────────

    private func rebuildFontIfNeeded(state: AppState) {
        guard
            state.cellSize         != lastCellSize ||
            state.characterSetType != lastCharSet  ||
            state.customChars      != lastCustom
        else { return }

        lastCellSize = state.cellSize
        lastCharSet  = state.characterSetType
        lastCustom   = state.customChars

        let fontSize = CGFloat(state.cellHeight) * 0.82
        let ct = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        ctFont = ct
        cgFont = CTFontCopyGraphicsFont(ct, nil)

        let chars = state.characters
        glyphs = chars.map { ch -> CGGlyph in
            var us = ch.utf16.first ?? 32
            var g  = CGGlyph(0)
            CTFontGetGlyphsForCharacters(ct, &us, &g, 1)
            return g
        }
    }

    // ── Core render ────────────────────────────────────────────────────────────

    private func render(
        source: CGImage,
        outputSize: CGSize,
        state: AppState,
        transparent: Bool = false,
        cellScale: Double = 1.0,
        clusters: [TrackerCluster] = []
    ) -> (CGImage?, CGRect) {

        let cellW = max(1, Int(Double(state.cellSize)   * cellScale))
        let cellH = max(1, Int(Double(state.cellHeight) * cellScale))

        // For scaled offline renders build a local font; otherwise use the display-link cache.
        let renderFont: CGFont
        let renderGlyphs: [CGGlyph]
        if abs(cellScale - 1.0) > 0.01 {
            let ct = CTFontCreateWithName("Menlo" as CFString, CGFloat(cellH) * 0.82, nil)
            renderFont   = CTFontCopyGraphicsFont(ct, nil)
            renderGlyphs = state.characters.map { ch -> CGGlyph in
                var us = ch.utf16.first ?? 32; var g = CGGlyph(0)
                CTFontGetGlyphsForCharacters(ct, &us, &g, 1); return g
            }
        } else {
            guard let cgf = cgFont, !glyphs.isEmpty else {
                return (nil, CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            renderFont   = cgf
            renderGlyphs = glyphs
        }

        let outW   = Int(outputSize.width)
        let outH   = Int(outputSize.height)

        // Aspect-correct letterbox / pillarbox
        let srcAspect  = Double(source.width) / Double(source.height)
        let viewAspect = outputSize.width / outputSize.height

        let renderW: Int
        let renderH: Int
        let offsetX: Int
        let offsetY: Int

        if srcAspect > viewAspect {
            renderW = outW
            renderH = max(Int(Double(outW) / srcAspect), cellH)
            offsetX = 0
            offsetY = (outH - renderH) / 2
        } else {
            renderH = outH
            renderW = max(Int(Double(outH) * srcAspect), cellW)
            offsetX = (outW - renderW) / 2
            offsetY = 0
        }

        // Normalized content rect — used by overlay to transform cluster coords
        let cRect = CGRect(
            x: CGFloat(offsetX) / CGFloat(outW),
            y: CGFloat(offsetY) / CGFloat(outH),
            width:  CGFloat(renderW) / CGFloat(outW),
            height: CGFloat(renderH) / CGFloat(outH)
        )

        let cols = max(renderW / cellW, 1)
        let rows = max(renderH / cellH, 1)

        guard let grid = sampleGrid(source, cols: cols, rows: rows) else {
            return (nil, cRect)
        }

        let cs  = CGColorSpaceCreateDeviceRGB()
        let bmi = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: outW * 4,
                                  space: cs, bitmapInfo: bmi)
        else { return (nil, cRect) }

        if !transparent {
            ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        }

        ctx.setFont(renderFont)
        ctx.setFontSize(CGFloat(cellH) * 0.82)

        let baseline = CGFloat(cellH) * 0.14
        let time     = Float(CACurrentMediaTime())
        let charCnt  = renderGlyphs.count

        // Batch cells by quantized color to minimise CGContext state changes
        struct Cell { var glyph: CGGlyph; var x, y: CGFloat }
        var batches = [UInt32: [Cell]]()
        batches.reserveCapacity(256)

        for row in 0..<rows {
            for col in 0..<cols {
                let si = (row * cols + col) * 4
                let r  = grid[si], g = grid[si+1], b = grid[si+2], a = grid[si+3]
                let alphaPass = state.invertAlpha ? (a < (1.0 - state.alphaThreshold)) : (a >= state.alphaThreshold)
                guard alphaPass else { continue }

                var luma = 0.299*r + 0.587*g + 0.114*b
                if state.invertLuma { luma = 1.0 - luma }
                luma = clamp01((luma - state.lumaThreshold) / max(1.0 - state.lumaThreshold, 1e-5))
                luma = pow(max(luma, 0), state.gamma)
                luma = clamp01((luma - 0.5) * state.contrast + 0.5)

                let ci = min(Int(luma * Float(charCnt - 1)), charCnt - 1)

                let (cr, cg, cb) = colorForCell(
                    r: r, g: g, b: b, luma: luma,
                    col: col, row: row, cols: cols, rows: rows,
                    state: state, time: time
                )

                let x = CGFloat(offsetX + col * cellW)
                let y = CGFloat((rows - 1 - row) * cellH + offsetY) + baseline

                let qr  = UInt32(min(Int(cr * 15), 15))
                let qg  = UInt32(min(Int(cg * 15), 15))
                let qb  = UInt32(min(Int(cb * 15), 15))
                let key = (qr << 8) | (qg << 4) | qb

                batches[key, default: []].append(Cell(glyph: renderGlyphs[ci], x: x, y: y))
            }
        }

        for (key, cells) in batches {
            let fr = CGFloat((key >> 8) & 0xF) / 15.0
            let fg = CGFloat((key >> 4) & 0xF) / 15.0
            let fb = CGFloat(key & 0xF) / 15.0
            ctx.setFillColor(red: fr, green: fg, blue: fb, alpha: 1)
            ctx.showGlyphs(cells.map { $0.glyph }, at: cells.map { CGPoint(x: $0.x, y: $0.y) })
        }

        if state.scanLineAnimation {
            let linePhase = Int(CACurrentMediaTime() * 60) % 3
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
            for row in 0..<rows {
                if ((rows - 1 - row) + linePhase) % 3 == 0 {
                    ctx.fill(CGRect(x: CGFloat(offsetX), y: CGFloat(row * cellH + offsetY),
                                    width: CGFloat(renderW), height: CGFloat(cellH)))
                }
            }
        }

        if state.trackerEnabled && !clusters.isEmpty {
            CPURenderer.drawTracker(clusters: clusters, contentRect: cRect, state: state,
                                    ctx: ctx, outW: outW, outH: outH, scale: cellScale)
        }

        return (ctx.makeImage(), cRect)
    }

    // MARK: – Tracker overlay (CoreGraphics — mirrors TrackerOverlayView's SwiftUI Canvas)

    static func drawTracker(
        clusters: [TrackerCluster],
        contentRect: CGRect,
        state: AppState,
        ctx: CGContext,
        outW: Int, outH: Int,
        scale: Double = 1.0
    ) {
        let sc  = CGFloat(scale)
        let cW  = CGFloat(outW)
        let cH  = CGFloat(outH)
        let sw  = CGFloat(state.strokeWidth) * sc
        let pad = CGFloat(state.boxPadding)

        // Normalized source coord → CGContext point.
        // Source y=0 is top; CGContext y=0 is bottom, so we flip.
        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(
                x: (contentRect.minX + nx * contentRect.width)  * cW,
                y: (contentRect.minY + (1.0 - ny) * contentRect.height) * cH
            )
        }

        func boxRect(_ b: CGRect) -> CGRect {
            let padded = b.insetBy(dx: -b.width * pad, dy: -b.height * pad)
            let tl = pt(padded.minX, padded.minY)
            let br = pt(padded.maxX, padded.maxY)
            return CGRect(x: tl.x, y: br.y, width: br.x - tl.x, height: tl.y - br.y)
        }

        // Connector lines
        if state.showConnectors && clusters.count > 1 {
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(state.connectorOpacity)))
            ctx.setLineWidth(sw)
            switch state.connectorStyle {
            case .solid:  ctx.setLineDash(phase: 0, lengths: [])
            case .dashed: ctx.setLineDash(phase: 0, lengths: [8 * sc, 5 * sc])
            case .dotted: ctx.setLineDash(phase: 0, lengths: [2 * sc, 4 * sc])
            }
            for i in 0..<(clusters.count - 1) {
                let a = clusters[i], b = clusters[i + 1]
                ctx.move(to: pt(a.center.x, a.center.y))
                ctx.addLine(to: pt(b.center.x, b.center.y))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Bounding boxes
        if state.showBoundingBoxes {
            ctx.saveGState()
            ctx.setLineWidth(sw)

            // Fill pass
            if state.showFill && state.boxStyle != .crosshair {
                let fc = NSColor(state.fillColor).usingColorSpace(.extendedSRGB) ?? NSColor(state.fillColor)
                ctx.setFillColor(fc.withAlphaComponent(CGFloat(state.fillOpacity)).cgColor)
                for cl in clusters {
                    let r  = boxRect(cl.bounds)
                    let cr = state.roundedCorners ? CGFloat(6) * sc : 0
                    ctx.addPath(CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil))
                }
                ctx.fillPath()
            }

            // Stroke pass
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            for cl in clusters {
                let r  = boxRect(cl.bounds)
                let cr = state.roundedCorners ? CGFloat(6) * sc : 0

                switch state.boxStyle {
                case .rect:
                    ctx.addPath(CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil))
                    ctx.strokePath()

                case .cornerHUD:
                    let arm = min(r.width, r.height) * 0.22
                    let p = CGMutablePath()
                    func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                        p.move(to: CGPoint(x: x, y: y + dy * arm))
                        p.addLine(to: CGPoint(x: x, y: y))
                        p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                    }
                    corner(r.minX, r.minY, +1, +1); corner(r.maxX, r.minY, -1, +1)
                    corner(r.maxX, r.maxY, -1, -1); corner(r.minX, r.maxY, +1, -1)
                    ctx.setLineCap(.square)
                    ctx.addPath(p); ctx.strokePath()
                    ctx.setLineCap(.butt)

                case .filled:
                    break // fill-only, no stroke

                case .crosshair:
                    let cpt  = pt(cl.center.x, cl.center.y)
                    let armW = r.width  * 0.55
                    let armH = r.height * 0.55
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: cpt.x - armW, y: cpt.y))
                    p.addLine(to: CGPoint(x: cpt.x + armW, y: cpt.y))
                    p.move(to: CGPoint(x: cpt.x, y: cpt.y - armH))
                    p.addLine(to: CGPoint(x: cpt.x, y: cpt.y + armH))
                    ctx.setLineCap(.square)
                    ctx.addPath(p); ctx.strokePath()
                    ctx.setLineCap(.butt)
                }
            }
            ctx.restoreGState()
        }

        // Labels
        if state.showLabels {
            let font = CTFontCreateWithName("Menlo-Regular" as CFString, 11 * sc, nil)
            for cl in clusters {
                let label: String
                switch state.labelContent {
                case .id:          label = "[\(cl.id)]"
                case .coordinates: label = String(format: "%.2f,%.2f", cl.center.x, cl.center.y)
                case .area:        label = String(format: "%.0fpx²", cl.area)
                case .confidence:  label = String(format: "%.0f%%", cl.confidence * 100)
                }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                ]
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: label, attributes: attrs)
                )
                let topLeft = pt(cl.bounds.minX, cl.bounds.minY)
                ctx.textPosition = CGPoint(x: topLeft.x + 4 * sc, y: topLeft.y + 4 * sc)
                CTLineDraw(line, ctx)
            }
        }
    }

    // ── Grid sampler ───────────────────────────────────────────────────────────

    private func sampleGrid(_ source: CGImage, cols: Int, rows: Int) -> [Float]? {
        let bpr = cols * 4
        guard let ctx = CGContext(data: nil, width: cols, height: rows,
                                  bitsPerComponent: 8, bytesPerRow: bpr,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let n = cols * rows * 4
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = Float(bytes[i]) / 255.0 }
        return out
    }

    // ── Color modes ────────────────────────────────────────────────────────────

    private func colorForCell(r: Float, g: Float, b: Float, luma: Float,
                               col: Int, row: Int, cols: Int, rows: Int,
                               state: AppState, time: Float) -> (Float, Float, Float) {
        var out: (Float, Float, Float)
        switch state.colorMode {

        case .mono:
            let c = state.monoColor.simd4f; out = (c.x, c.y, c.z)

        case .source:
            out = (r, g, b)

        case .analogous:
            let hsl    = rgb2hsl(r, g, b)
            let spread = state.analogousSpread / 360.0
            let cnt    = max(state.analogousCount, 1)
            let slot   = luma * Float(cnt - 1)
            let delta  = cnt > 1 ? (slot / Float(cnt - 1) - 0.5) * spread * 2.0 : 0
            let hue    = posMod(hsl.0 + delta, 1.0)
            out = hsl2rgb(hue, max(hsl.1, 0.5), hsl.2)

        case .hueShift:
            let hsl = rgb2hsl(r, g, b)
            let hue = posMod(hsl.0 + time * 0.12, 1.0)
            out = hsl2rgb(hue, max(hsl.1, 0.4), hsl.2)

        case .gradient:
            let t  = Float(row) / Float(max(rows - 1, 1))
            let pc = state.primaryColor.simd4f
            let sc = state.secondaryColor.simd4f
            out = (lerp(pc.x, sc.x, t), lerp(pc.y, sc.y, t), lerp(pc.z, sc.z, t))

        case .neon:
            let hue = posMod(Float(col)/Float(cols) * 0.35 + Float(row)/Float(rows) * 0.25 + time * 0.18, 1.0)
            out = hsl2rgb(hue, 1.0, 0.55)

        case .thermal:
            out = thermalColor(luma)

        case .glitch:
            let seed = hash21(Float(col), Float(row) + floor(time * 14.0))
            let hue  = posMod(seed + time * 0.08, 1.0)
            out = hsl2rgb(hue, 1.0, 0.5)
        }

        var hsl = rgb2hsl(out.0, out.1, out.2)
        hsl.0 = posMod(hsl.0 + state.hueShift / 360.0, 1.0)
        hsl.1 = clamp01(hsl.1 * state.saturation)
        hsl.2 = clamp01(hsl.2 * state.brightness)
        out = hsl2rgb(hsl.0, hsl.1, hsl.2)

        let ov = state.sourceOverlayBlend
        return (lerp(out.0, r, ov), lerp(out.1, g, ov), lerp(out.2, b, ov))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Color math helpers
// ─────────────────────────────────────────────────────────────────────────────

private func rgb2hsl(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
    let mx = max(r, max(g, b)), mn = min(r, min(g, b))
    let l  = (mx + mn) * 0.5
    var s: Float = 0, h: Float = 0
    let d = mx - mn
    if d > 1e-5 {
        s = d / (1.0 - abs(2*l - 1))
        if mx == r      { h = fmod((g - b) / d, 6) / 6 }
        else if mx == g { h = ((b - r) / d + 2) / 6 }
        else            { h = ((r - g) / d + 4) / 6 }
        if h < 0 { h += 1 }
    }
    return (h, s, l)
}

private func hsl2rgb(_ h: Float, _ s: Float, _ l: Float) -> (Float, Float, Float) {
    let c = (1.0 - abs(2*l - 1)) * s
    let x = c * (1.0 - abs(fmod(h * 6, 2.0) - 1.0))
    let m = l - c * 0.5
    let r, g, b: Float
    if      h < 1/6.0 { r = c; g = x; b = 0 }
    else if h < 2/6.0 { r = x; g = c; b = 0 }
    else if h < 3/6.0 { r = 0; g = c; b = x }
    else if h < 4/6.0 { r = 0; g = x; b = c }
    else if h < 5/6.0 { r = x; g = 0; b = c }
    else              { r = c; g = 0; b = x }
    return (clamp01(r+m), clamp01(g+m), clamp01(b+m))
}

private func thermalColor(_ t: Float) -> (Float, Float, Float) {
    let stops: [(Float, Float, Float, Float)] = [
        (0.00, 0.0, 0.0, 0.5),
        (0.25, 0.0, 0.8, 0.8),
        (0.50, 0.8, 0.8, 0.0),
        (0.75, 1.0, 0.3, 0.0),
        (1.00, 1.0, 1.0, 1.0),
    ]
    for i in 0..<(stops.count - 1) {
        let (t0, r0, g0, b0) = stops[i]
        let (t1, r1, g1, b1) = stops[i+1]
        if t >= t0 && t <= t1 {
            let f = (t - t0) / (t1 - t0)
            return (lerp(r0, r1, f), lerp(g0, g1, f), lerp(b0, b1, f))
        }
    }
    return (1, 1, 1)
}

private func hash21(_ x: Float, _ y: Float) -> Float {
    fract(sin(x * 12.9898 + y * 78.233) * 43758.5453)
}

@inline(__always) private func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }
@inline(__always) private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) private func posMod(_ v: Float, _ m: Float) -> Float {
    let r = v.truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r
}
@inline(__always) private func fract(_ v: Float) -> Float { v - floor(v) }
