import SwiftUI
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – HUD Keyframe model
// ─────────────────────────────────────────────────────────────────────────────

struct HUDKeyframe: Identifiable, Equatable {
    var id: UUID = UUID()
    var time: Double         // video time in seconds

    enum Kind: Equatable {
        case scope(Float)    // scope progress value: 0=open, 1=fully closed
        case lock            // trigger the lock-acquired animation at this time
    }
    var kind: Kind

    var isScopeKF: Bool  { if case .scope = kind { return true }; return false }
    var isLockKF:  Bool  { if case .lock  = kind { return true }; return false }
    var scopeValue: Float? { if case .scope(let v) = kind { return v }; return nil }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – App state
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class AppState {

    // ── Source ───────────────────────────────────────────────────────────────
    var sourceURL: URL? = nil
    var isImage: Bool = false
    var isVideo: Bool = false
    var isSequence: Bool = false

    // ── Render ───────────────────────────────────────────────────────────────
    var characterSetType: CharacterSetType = .standard
    var customChars: String = "@#S%?*+;:,. "
    var cellSize: Int = 12              // cell width px; height = cellSize * 2
    var minCellSize: Int = 4
    var maxCellSize: Int = 32
    var dynamicScaling: Bool = false
    var invertLuma: Bool = false
    var lumaThreshold: Float = 0.0
    var contrast: Float = 1.0
    var gamma: Float = 1.0
    var alphaThreshold: Float = 0.1
    var invertAlpha: Bool = false

    // ── Color ─────────────────────────────────────────────────────────────────
    var colorMode: ColorMode = .source
    var monoColor: Color = .white
    var primaryColor: Color = Color(red: 0.2, green: 0.9, blue: 1.0)
    var secondaryColor: Color = Color(red: 0.8, green: 0.2, blue: 0.0)
    var hueShift: Float = 0.0
    var saturation: Float = 1.0
    var brightness: Float = 1.0
    var analogousSpread: Float = 30.0
    var analogousCount: Int = 3
    var cycleAnimation: Bool = false
    var sourceOverlayBlend: Float = 0.0

    // ── Tracker ───────────────────────────────────────────────────────────────
    var trackerEnabled: Bool = false
    var detectionMode: DetectionMode = .bright
    var maxClusters: Int = 5
    var sensitivity: Float = 0.5
    var minArea: Float = 50
    var showBoundingBoxes: Bool = true
    var boxStyle: BoxStyle = .cornerHUD
    var roundedCorners: Bool = false
    var strokeWidth: Float = 1.5
    var boxPadding: Float = 0.0          // expands/shrinks bounds (-1…1 relative to box size)
    var showFill: Bool = false
    var fillOpacity: Float = 0.15
    var fillColor: Color = .white
    var showConnectors: Bool = true
    var connectorOpacity: Float = 0.6
    var connectorStyle: LineStyle = .dashed
    var showLabels: Bool = true
    var labelContent: LabelContent = .id
    var scanLineAnimation: Bool = false
    var showCenterDot: Bool = false
    var centerDotSize: Float = 4.0
    var showMotionTrails: Bool = false
    var trailLength: Int = 15
    var singleTarget: Bool = false
    var targetSmoothness: Float = 0.72
    var boxColor: Color = .white

    // Region of interest — tracker only detects inside this zone
    var trackerROIEnabled: Bool = false
    var trackerROIX: Float = 0.15   // normalized left edge
    var trackerROIY: Float = 0.15   // normalized top edge
    var trackerROIW: Float = 0.70   // normalized width
    var trackerROIH: Float = 0.70   // normalized height

    // ── Composite ─────────────────────────────────────────────────────────────
    var compositeMode: CompositeMode = .passthrough
    var overlayOpacity: Float = 0.75

    // ── HUD ───────────────────────────────────────────────────────────────────
    var hudEnabled: Bool = false
    var hudTintEnabled: Bool = false
    var hudTintColor: Color = Color(red: 0.18, green: 0.95, blue: 0.30)
    var hudTintOpacity: Float = 0.08
    var hudVignetteEnabled: Bool = true
    var hudVignetteStrength: Float = 0.50
    var hudScanLineEnabled: Bool = false
    var hudScanSpeed: Float = 0.60
    var hudCornerFramesEnabled: Bool = true
    var hudDataEnabled: Bool = false
    var hudCrosshairEnabled: Bool = false
    var hudCompassEnabled: Bool = true
    var hudCompassSpeed: Float = 4.0        // degrees per second drift
    var hudRangeCallouts: Bool = true
    var hudMargin: Float = 0.0
    var hudScale: Float = 1.0
    var hudReticleRing: Bool = false
    var hudMildots: Bool = false
    var hudBDCMarks: Bool = false
    var hudWindMarks: Bool = false
    var hudScopeFrame: Bool = false
    var hudScopeRadius: Float = 0.88
    var hudDataPane: Bool = false
    var hudNVMode: Bool = false
    var hudLevelIndicator: Bool = false
    var hudSweepArc: Bool = false
    var hudPulseRings: Bool = false
    var hudBreathPause: Bool = false
    var hudStadiaCircles: Bool = false
    var hudElevMarks: Bool = false
    var hudAcquisitionBrackets: Bool = false

    // Sizing — important for 4K
    var hudStrokeWidth: Float = 1.0        // line thickness multiplier
    var hudTextScale: Float = 1.0          // text size multiplier

    // Mid-field elements (zone between center reticle and screen edges)
    var hudOuterBox: Bool = false           // corner-bracket box centered on frame
    var hudOuterBoxSize: Float = 0.38      // half-size as fraction of min(fW,fH)
    var hudRangeArcs: Bool = false          // partial arcs at multiple radii w/ distance labels
    var hudHorizRef: Bool = false           // long thin horizontal reference lines from center
    var hudAnglemarks: Bool = false         // clock-position tick marks around reticle
    var hudTacticalGrid: Bool = false       // subtle full-frame dot grid
    var hudLateralScale: Bool = false       // vertical ruler bars on left/right mid-sides
    var hudSignalBars: Bool = false         // IR signal-strength bar graph (right side)
    var hudCrosswindArrow: Bool = false     // animated crosswind arrow with speed readout

    // New mid-field elements
    var hudRangeTickFrame: Bool = false     // secondary corner-bracket frame (55% of outer box) with graduation ticks
    var hudPerimeterRing: Bool = false      // 24-tick azimuth reference ring at mid-field radius
    var hudThreatDiamond: Bool = false      // threat sector diamonds at 4 diagonal positions
    var hudLockArc: Bool = false            // sector-scan lock acquisition arc (8 sectors, holds then steps)

    // Scope zoom animation — 0=full open view, 1=fully scoped in (manual slider)
    var hudScopeProgress: Float = 1.0

    // Lock animation — set when tracker confidence exceeds threshold
    var hudLockTime: Date? = nil

    // HUD keyframes — added from the timeline transport bar
    var hudKeyframes: [HUDKeyframe] = []

    // Video time — synced from VideoProcessor for keyframe evaluation
    var videoCurrentTime: Double = 0

    // Boot animation — set to Date() when HUD is enabled; drives 2s init sequence
    var hudInitTime: Date? = nil

    // ── Active preset ─────────────────────────────────────────────────────────
    var activePresetName: String? = nil

    // ── AE Bridge ─────────────────────────────────────────────────────────────
    var aeBridgeEnabled: Bool = false
    var aeBridgeFolder: URL? = nil

    // ── Computed ──────────────────────────────────────────────────────────────
    var characters: [Character] {
        characterSetType == .custom
            ? Array(customChars.isEmpty ? "@#S%?*+;:,. " : customChars)
            : characterSetType.characters
    }

    var cellHeight: Int { cellSize * 2 }

    // ── Apply Preset ──────────────────────────────────────────────────────────
    func apply(_ p: Preset) {
        characterSetType  = p.characterSetType
        customChars       = p.customChars
        cellSize          = p.cellSize
        minCellSize       = p.minCellSize
        maxCellSize       = p.maxCellSize
        dynamicScaling    = p.dynamicScaling
        invertLuma        = p.invertLuma
        lumaThreshold     = p.lumaThreshold
        contrast          = p.contrast
        gamma             = p.gamma
        alphaThreshold    = p.alphaThreshold

        colorMode         = p.colorMode
        monoColor         = Color(red: Double(p.monoColorR), green: Double(p.monoColorG), blue: Double(p.monoColorB))
        primaryColor      = Color(red: Double(p.primaryColorR), green: Double(p.primaryColorG), blue: Double(p.primaryColorB))
        secondaryColor    = Color(red: Double(p.secondaryColorR), green: Double(p.secondaryColorG), blue: Double(p.secondaryColorB))
        hueShift          = p.hueShift
        saturation        = p.saturation
        brightness        = p.brightness
        analogousSpread   = p.analogousSpread
        analogousCount    = p.analogousCount
        cycleAnimation    = p.cycleAnimation
        sourceOverlayBlend = p.sourceOverlayBlend

        trackerEnabled    = p.trackerEnabled
        detectionMode     = p.detectionMode
        maxClusters       = p.maxClusters
        sensitivity       = p.sensitivity
        minArea           = p.minArea
        showBoundingBoxes = p.showBoundingBoxes
        boxStyle          = p.boxStyle
        roundedCorners    = p.roundedCorners
        strokeWidth       = p.strokeWidth
        boxPadding        = p.boxPadding
        showFill          = p.showFill
        fillOpacity       = p.fillOpacity
        fillColor         = Color(red: Double(p.fillColorR), green: Double(p.fillColorG), blue: Double(p.fillColorB))
        showConnectors    = p.showConnectors
        connectorOpacity  = p.connectorOpacity
        connectorStyle    = p.connectorStyle
        showLabels        = p.showLabels
        labelContent      = p.labelContent
        scanLineAnimation  = p.scanLineAnimation
        showCenterDot      = p.showCenterDot
        centerDotSize      = p.centerDotSize
        showMotionTrails   = p.showMotionTrails
        trailLength        = p.trailLength
        singleTarget       = p.singleTarget
        targetSmoothness   = p.targetSmoothness
        boxColor           = Color(red: Double(p.boxColorR), green: Double(p.boxColorG), blue: Double(p.boxColorB))
        compositeMode      = p.compositeMode
        overlayOpacity     = p.overlayOpacity

        activePresetName  = p.name
    }

    func snapshot() -> Preset {
        var p = Preset(name: activePresetName ?? "Untitled")
        p.characterSetType   = characterSetType
        p.customChars        = customChars
        p.cellSize           = cellSize
        p.minCellSize        = minCellSize
        p.maxCellSize        = maxCellSize
        p.dynamicScaling     = dynamicScaling
        p.invertLuma         = invertLuma
        p.lumaThreshold      = lumaThreshold
        p.contrast           = contrast
        p.gamma              = gamma
        p.alphaThreshold     = alphaThreshold
        p.colorMode          = colorMode
        let mc = NSColor(monoColor)
        p.monoColorR = Float(mc.redComponent); p.monoColorG = Float(mc.greenComponent); p.monoColorB = Float(mc.blueComponent)
        let pc = NSColor(primaryColor)
        p.primaryColorR = Float(pc.redComponent); p.primaryColorG = Float(pc.greenComponent); p.primaryColorB = Float(pc.blueComponent)
        let sc = NSColor(secondaryColor)
        p.secondaryColorR = Float(sc.redComponent); p.secondaryColorG = Float(sc.greenComponent); p.secondaryColorB = Float(sc.blueComponent)
        p.hueShift           = hueShift
        p.saturation         = saturation
        p.brightness         = brightness
        p.analogousSpread    = analogousSpread
        p.analogousCount     = analogousCount
        p.cycleAnimation     = cycleAnimation
        p.sourceOverlayBlend = sourceOverlayBlend
        p.trackerEnabled     = trackerEnabled
        p.detectionMode      = detectionMode
        p.maxClusters        = maxClusters
        p.sensitivity        = sensitivity
        p.minArea            = minArea
        p.showBoundingBoxes  = showBoundingBoxes
        p.boxStyle           = boxStyle
        p.roundedCorners     = roundedCorners
        p.strokeWidth        = strokeWidth
        p.boxPadding         = boxPadding
        p.showFill           = showFill
        p.fillOpacity        = fillOpacity
        let fc = NSColor(fillColor).usingColorSpace(.extendedSRGB) ?? NSColor(fillColor)
        p.fillColorR = Float(fc.redComponent); p.fillColorG = Float(fc.greenComponent); p.fillColorB = Float(fc.blueComponent)
        p.showConnectors     = showConnectors
        p.connectorOpacity   = connectorOpacity
        p.connectorStyle     = connectorStyle
        p.showLabels         = showLabels
        p.labelContent       = labelContent
        p.scanLineAnimation  = scanLineAnimation
        p.showCenterDot      = showCenterDot
        p.centerDotSize      = centerDotSize
        p.showMotionTrails   = showMotionTrails
        p.trailLength        = trailLength
        p.singleTarget       = singleTarget
        p.targetSmoothness   = targetSmoothness
        let bxc = NSColor(boxColor).usingColorSpace(.extendedSRGB) ?? NSColor(boxColor)
        p.boxColorR = Float(bxc.redComponent); p.boxColorG = Float(bxc.greenComponent); p.boxColorB = Float(bxc.blueComponent)
        p.compositeMode      = compositeMode
        p.overlayOpacity     = overlayOpacity
        return p
    }
}

// MARK: – Color helpers
extension Color {
    var simd4f: SIMD4<Float> {
        let c = NSColor(self).usingColorSpace(.extendedSRGB) ?? NSColor(self)
        return SIMD4<Float>(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(c.alphaComponent))
    }
}
