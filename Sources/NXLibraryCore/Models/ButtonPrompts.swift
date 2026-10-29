import Foundation

public enum ButtonNameStyle: String, Codable, CaseIterable, Identifiable {
    case automatic, nintendo, xbox, playstation

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public enum PromptButton: String, CaseIterable {
    case a, b, x, y, lb, rb, lt, rt, rs, view, menu
}

public enum ConnectedPad {
    case nintendo, xbox, playstation, other, none
}

public enum ButtonPrompts {
    public static func label(_ button: PromptButton, style: ButtonNameStyle, connected: ConnectedPad) -> String {
        switch resolved(style, connected) {
        case .nintendo: return nintendoLabel(button)
        case .playstation: return playstationLabel(button)
        default: return xboxLabel(button)
        }
    }

    private static func resolved(_ style: ButtonNameStyle, _ connected: ConnectedPad) -> ButtonNameStyle {
        guard style == .automatic else { return style }
        switch connected {
        case .nintendo: return .nintendo
        case .playstation: return .playstation
        default: return .xbox
        }
    }

    private static func nintendoLabel(_ b: PromptButton) -> String {
        switch b {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .lb: return "L"
        case .rb: return "R"
        case .lt: return "ZL"
        case .rt: return "ZR"
        case .rs: return "RS"
        case .view: return "−"
        case .menu: return "+"
        }
    }

    private static func xboxLabel(_ b: PromptButton) -> String {
        switch b {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .lb: return "LB"
        case .rb: return "RB"
        case .lt: return "LT"
        case .rt: return "RT"
        case .rs: return "RS"
        case .view: return "View"
        case .menu: return "Menu"
        }
    }

    private static func playstationLabel(_ b: PromptButton) -> String {
        switch b {
        case .a: return "✕"
        case .b: return "○"
        case .x: return "□"
        case .y: return "△"
        case .lb: return "L1"
        case .rb: return "R1"
        case .lt: return "L2"
        case .rt: return "R2"
        case .rs: return "R3"
        case .view: return "Create"
        case .menu: return "Options"
        }
    }
}
