import Foundation

public enum GamepadBrand: String, CaseIterable, Identifiable {
    case nintendoSwitch = "Nintendo Switch"
    case xbox = "Xbox Series / One"
    case playstation = "PlayStation DualShock / DualSense"
    case generic = "8BitDo / Generic Gamepad"
    
    public var id: String { rawValue }
    
    public var confirmButtonName: String {
        switch self {
        case .nintendoSwitch: return "A (Confirm)"
        case .xbox: return "A (Confirm)"
        case .playstation: return "✕ (Confirm)"
        case .generic: return "A (Confirm)"
        }
    }
    
    public var cancelButtonName: String {
        switch self {
        case .nintendoSwitch: return "B (Back)"
        case .xbox: return "B (Back)"
        case .playstation: return "○ (Back)"
        case .generic: return "B (Back)"
        }
    }
    
    public var secondaryButtonName: String {
        switch self {
        case .nintendoSwitch: return "X (Settings)"
        case .xbox: return "X (Settings)"
        case .playstation: return "□ (Settings)"
        case .generic: return "X (Settings)"
        }
    }
    
    public var contextButtonName: String {
        switch self {
        case .nintendoSwitch: return "Y (Save Folder)"
        case .xbox: return "Y (Save Folder)"
        case .playstation: return "△ (Save Folder)"
        case .generic: return "Y (Save Folder)"
        }
    }
    
    public var shoulderTabsPrompt: String {
        switch self {
        case .nintendoSwitch: return "L / R"
        case .xbox: return "LB / RB"
        case .playstation: return "L1 / R1"
        case .generic: return "L / R"
        }
    }

    public var menuButtonGlyph: String {
        switch self {
        case .nintendoSwitch: return "＋"
        case .playstation: return "☰"
        case .xbox, .generic: return "≡"
        }
    }
}

public enum GamepadAction: Hashable {
    case navigateUp
    case navigateDown
    case navigateLeft
    case navigateRight
    case confirm           // A or Cross
    case cancel            // B or Circle
    case secondaryAction   // X or Square (Settings)
    case contextAction     // Y or Triangle (Save files)
    case tabPrevious       // Left Shoulder (L / LB)
    case tabNext           // Right Shoulder (R / RB)
    case menu              // Plus / Start (tap)
    case menuHold          // Plus / Start (hold)
    case view              // Minus / Select / Share (tap)
    case viewHold          // Minus / Select / Share (hold)
    case jumpToStart       // Left trigger
    case jumpToEnd         // Right trigger
    case rightStickPress   // R3
}
