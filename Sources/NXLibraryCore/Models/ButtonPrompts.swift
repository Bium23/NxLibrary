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

/// A Mac keyboard key as a prompt: an SF Symbol or the key's printed text.
public enum KeyCap: Equatable {
    case symbol(String)
    case text(String)
}

public enum ButtonPrompts {
    /// Automatic names with no controller connected show the keyboard keys instead.
    public static func usesKeyboard(style: ButtonNameStyle, connected: ConnectedPad) -> Bool {
        style == .automatic && connected == .none
    }

    /// The key the screens' key monitors take for each prompt: Return confirms,
    /// Esc goes back, X and Y, Q/E for the shoulders (E also steps the filter),
    /// Home/End for the triggers, Tab for View and ⌘K for Menu.
    public static func keyboardKey(_ button: PromptButton) -> KeyCap {
        switch button {
        case .a: return .symbol("return")
        case .b: return .text("esc")
        case .x: return .text("X")
        case .y: return .text("Y")
        case .lb: return .text("Q")
        case .rb, .rs: return .text("E")
        case .lt: return .text("home")
        case .rt: return .text("end")
        case .view: return .text("tab")
        case .menu: return .text("⌘K")
        }
    }
    public static func label(_ button: PromptButton, style: ButtonNameStyle, connected: ConnectedPad) -> String {
        switch resolved(style, connected) {
        case .nintendo: return nintendoLabel(button)
        case .playstation: return playstationLabel(button)
        default: return xboxLabel(button)
        }
    }

    /// The SF Symbols name for a prompt (Apple's controller glyphs), or nil.
    /// Automatic with a controller connected prefers what the controller itself
    /// reports (`GCControllerElement.sfSymbolsName`, which follows the user's
    /// remapping), then that brand's table; a generic controller uses Xbox's.
    /// Automatic with no controller has none (`keyboardKey` applies); a chosen
    /// style always uses its table.
    public static func symbol(_ button: PromptButton, style: ButtonNameStyle, connected: ConnectedPad,
                              reported: [PromptButton: String] = [:]) -> String? {
        if style == .automatic {
            guard connected != .none else { return nil }
            if let name = reported[button], !name.isEmpty, !isGenericShape(name) { return name }
        }
        switch resolved(style, connected) {
        case .nintendo: return nintendoSymbol(button)
        case .playstation: return playstationSymbol(button)
        default: return xboxSymbol(button)
        }
    }

    /// Shape-only placeholders have no button mark to show in a two-colour badge.
    /// Keep real glyphs such as `circle.circle`, `square.circle` and stacked rectangles.
    public static func isGenericShape(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        guard let shape = parts.first, genericShapes.contains(String(shape)) else { return false }
        return parts.dropFirst().allSatisfy { shapeModifiers.contains(String($0)) }
    }

    private static let genericShapes: Set<String> = ["circle", "capsule", "square", "rectangle", "oval", "button"]
    private static let shapeModifiers: Set<String> = [
        "fill", "portrait", "landscape", "horizontal", "vertical", "roundedtop", "roundedbottom",
        "inset", "filled", "dashed", "dotted", "lefthalf", "righthalf", "tophalf", "bottomhalf"
    ]

    private static func nintendoSymbol(_ b: PromptButton) -> String {
        switch b {
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .lb: return "l.rectangle.roundedbottom"
        case .rb: return "r.rectangle.roundedbottom"
        case .lt: return "zl.rectangle.roundedtop"
        case .rt: return "zr.rectangle.roundedtop"
        case .rs: return "r.joystick.press.down"
        case .view: return "minus.circle"
        case .menu: return "plus.circle"
        }
    }

    private static func xboxSymbol(_ b: PromptButton) -> String {
        switch b {
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .lb: return "lb.rectangle.roundedbottom"
        case .rb: return "rb.rectangle.roundedbottom"
        case .lt: return "lt.rectangle.roundedtop"
        case .rt: return "rt.rectangle.roundedtop"
        case .rs: return "r.joystick.press.down"
        case .view: return "rectangle.on.rectangle.circle"
        case .menu: return "line.3.horizontal.circle"
        }
    }

    private static func playstationSymbol(_ b: PromptButton) -> String {
        switch b {
        case .a: return "xmark.circle"
        case .b: return "circle.circle"
        case .x: return "square.circle"
        case .y: return "triangle.circle"
        case .lb: return "l1.rectangle.roundedbottom"
        case .rb: return "r1.rectangle.roundedbottom"
        case .lt: return "l2.rectangle.roundedtop"
        case .rt: return "r2.rectangle.roundedtop"
        case .rs: return "r.joystick.press.down"
        case .view: return "square.and.arrow.up.circle"
        case .menu: return "line.3.horizontal.circle"
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
