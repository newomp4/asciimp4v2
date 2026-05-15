import CoreGraphics

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
