import SwiftUI
import Observation

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
    var minArea: Float = 500
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

    // ── Composite ─────────────────────────────────────────────────────────────
    var compositeMode: CompositeMode = .replace
    var overlayOpacity: Float = 0.75

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
