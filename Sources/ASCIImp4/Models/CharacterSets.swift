import Foundation

enum CharacterSetType: String, CaseIterable, Codable {
    case standard  = "Standard"
    case numbers   = "Numbers"
    case binary    = "Binary"
    case letters   = "Letters"
    case symbols   = "Symbols"
    case blocks    = "Blocks"
    case hex       = "Hex"
    case custom    = "Custom"

    // Dense → sparse (maps high luma → sparse char by default; invert for inverted look)
    var characters: [Character] {
        switch self {
        case .standard: return Array("@#S%?*+;:,. ")
        case .numbers:  return Array("8086543219 7 ")
        case .binary:   return Array("1100110101000 ")
        case .letters:  return Array("WMBHKXDFPQANUCYEROZTLJSVIwmhkxdfpqancuerzotljsvi. ")
        case .symbols:  return Array("@#$%&*+=<>!?/\\|~^`'\",.:; ")
        case .blocks:   return Array("█▓▒░ ")
        case .hex:      return Array("0123456789ABCDEFabcdef ")
        case .custom:   return Array("@#S%?*+;:,. ")
        }
    }
}
