import Foundation

enum ColorMode: Int, CaseIterable, Codable {
    case mono       = 0
    case source     = 1
    case analogous  = 2
    case hueShift   = 3
    case gradient   = 4
    case neon       = 5
    case thermal    = 6
    case glitch     = 7

    var label: String {
        switch self {
        case .mono:      return "Mono"
        case .source:    return "Source"
        case .analogous: return "Analogous"
        case .hueShift:  return "Hue Shift"
        case .gradient:  return "Gradient"
        case .neon:      return "Neon"
        case .thermal:   return "Thermal"
        case .glitch:    return "Glitch"
        }
    }

    var description: String {
        switch self {
        case .mono:      return "Single solid color for all characters"
        case .source:    return "Samples original pixel colors from the source"
        case .analogous: return "Harmonic palette derived from source hue"
        case .hueShift:  return "Animated hue rotation over time"
        case .gradient:  return "Top-to-bottom blend from primary to secondary"
        case .neon:      return "Cycling high-saturation hues"
        case .thermal:   return "Cool-to-hot thermal color map"
        case .glitch:    return "Randomized per-character color"
        }
    }
}
