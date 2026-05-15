import Foundation
import SwiftUI

struct Preset: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var isBuiltin: Bool = false

    // Render
    var characterSetType: CharacterSetType = .standard
    var customChars: String = "@#S%?*+;:,. "
    var cellSize: Int = 12
    var minCellSize: Int = 4
    var maxCellSize: Int = 32
    var dynamicScaling: Bool = false
    var invertLuma: Bool = false
    var lumaThreshold: Float = 0.0
    var contrast: Float = 1.0
    var gamma: Float = 1.0
    var alphaThreshold: Float = 0.1

    // Color
    var colorMode: ColorMode = .source
    var monoColorR: Float = 1; var monoColorG: Float = 1; var monoColorB: Float = 1
    var primaryColorR: Float = 0.2; var primaryColorG: Float = 0.9; var primaryColorB: Float = 1.0
    var secondaryColorR: Float = 0.8; var secondaryColorG: Float = 0.2; var secondaryColorB: Float = 0.0
    var hueShift: Float = 0.0
    var saturation: Float = 1.0
    var brightness: Float = 1.0
    var analogousSpread: Float = 30.0
    var analogousCount: Int = 3
    var cycleAnimation: Bool = false
    var sourceOverlayBlend: Float = 0.0

    // Tracker
    var trackerEnabled: Bool = false
    var detectionMode: DetectionMode = .bright
    var maxClusters: Int = 5
    var sensitivity: Float = 0.5
    var minArea: Float = 500
    var showBoundingBoxes: Bool = true
    var boxStyle: BoxStyle = .cornerHUD
    var roundedCorners: Bool = false
    var strokeWidth: Float = 1.5
    var boxPadding: Float = 0.0
    var showFill: Bool = false
    var fillOpacity: Float = 0.15
    var fillColorR: Float = 1; var fillColorG: Float = 1; var fillColorB: Float = 1
    var showConnectors: Bool = true
    var connectorOpacity: Float = 0.6
    var connectorStyle: LineStyle = .dashed
    var showLabels: Bool = true
    var labelContent: LabelContent = .id
    var scanLineAnimation: Bool = false

    // ── Built-in presets ─────────────────────────────────────────────────────

    static let builtins: [Preset] = [
        {
            var p = Preset(name: "Binary Glitch", isBuiltin: true)
            p.characterSetType = .binary
            p.colorMode = .glitch
            p.cellSize = 10
            p.contrast = 1.4
            p.scanLineAnimation = true
            return p
        }(),
        {
            var p = Preset(name: "Warm Analog", isBuiltin: true)
            p.characterSetType = .standard
            p.colorMode = .analogous
            p.primaryColorR = 1.0; p.primaryColorG = 0.6; p.primaryColorB = 0.2
            p.analogousSpread = 40
            p.analogousCount = 5
            p.saturation = 1.2
            p.gamma = 0.9
            return p
        }(),
        {
            var p = Preset(name: "Cold Scan", isBuiltin: true)
            p.characterSetType = .symbols
            p.colorMode = .mono
            p.monoColorR = 0.4; p.monoColorG = 0.9; p.monoColorB = 1.0
            p.contrast = 1.3
            p.scanLineAnimation = true
            p.trackerEnabled = true
            return p
        }(),
        {
            var p = Preset(name: "Matrix", isBuiltin: true)
            p.characterSetType = .letters
            p.colorMode = .mono
            p.monoColorR = 0.1; p.monoColorG = 1.0; p.monoColorB = 0.3
            p.cellSize = 8
            p.contrast = 1.5
            p.gamma = 0.8
            return p
        }(),
        {
            var p = Preset(name: "Thermal Vision", isBuiltin: true)
            p.characterSetType = .blocks
            p.colorMode = .thermal
            p.invertLuma = true
            p.contrast = 1.2
            p.trackerEnabled = true
            p.detectionMode = .bright
            p.maxClusters = 3
            return p
        }(),
        {
            var p = Preset(name: "Hex Data", isBuiltin: true)
            p.characterSetType = .hex
            p.colorMode = .gradient
            p.primaryColorR = 0.0; p.primaryColorG = 0.8; p.primaryColorB = 1.0
            p.secondaryColorR = 0.0; p.secondaryColorG = 0.3; p.secondaryColorB = 0.6
            p.cellSize = 9
            return p
        }(),
        {
            var p = Preset(name: "Neon Outline", isBuiltin: true)
            p.characterSetType = .symbols
            p.colorMode = .neon
            p.sourceOverlayBlend = 0.15
            p.contrast = 1.6
            p.lumaThreshold = 0.2
            return p
        }(),
        {
            var p = Preset(name: "Retro Terminal", isBuiltin: true)
            p.characterSetType = .standard
            p.colorMode = .mono
            p.monoColorR = 1.0; p.monoColorG = 0.75; p.monoColorB = 0.3
            p.cellSize = 11
            p.gamma = 1.2
            p.brightness = 0.95
            return p
        }()
    ]
}
