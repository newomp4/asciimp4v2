import CoreGraphics

enum CompositeMode: String, CaseIterable, Codable {
    case replace     = "Replace"
    case passthrough = "Video"
    case overlay     = "Overlay"
    case multiply    = "Multiply"
    case screen      = "Screen"

    var description: String {
        switch self {
        case .replace:     return "ASCII replaces the source — no video beneath"
        case .passthrough: return "Source video plays normally — tracker overlaid on top, no ASCII"
        case .overlay:     return "ASCII drawn over source video at adjustable opacity"
        case .multiply:    return "ASCII multiplied into source — darkening effect"
        case .screen:      return "ASCII screened over source — brightening effect"
        }
    }
}

enum DetectionMode: String, CaseIterable, Codable {
    case bright  = "Bright"
    case dark    = "Dark"
    case edge    = "Edge"
    case motion  = "Motion"
    case random  = "Random"
}

enum BoxStyle: String, CaseIterable, Codable {
    case rect      = "Rect"
    case cornerHUD = "Corner"
    case filled    = "Filled"
    case crosshair = "Cross"
}

enum LineStyle: String, CaseIterable, Codable {
    case solid  = "Solid"
    case dashed = "Dashed"
    case dotted = "Dotted"
}

enum LabelContent: String, CaseIterable, Codable {
    case id          = "ID"
    case coordinates = "Coords"
    case area        = "Area"
    case confidence  = "Confidence"
}

struct TrackerCluster: Identifiable, Equatable {
    let id: Int
    let center: CGPoint
    let bounds: CGRect
    let area: CGFloat
    let confidence: Float
}
