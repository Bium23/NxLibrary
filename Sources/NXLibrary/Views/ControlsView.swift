import SwiftUI

public struct ControlsView: View {
    public init() {}

    private let mappingColumns = [
        GridItem(.adaptive(minimum: 340, maximum: .infinity),
                 spacing: 12,
                 alignment: .top)
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ControllerStatusPanel()
                mappingPanel
                touchPanel
                gamepadPanel
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 36)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(SeleneTheme.scrim)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Controls & Keyboard Mapping")
                    .seleneFont(34, .bold)
                    .tracking(-1.1)
                    .foregroundColor(SeleneTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Games in NX Library simultaneously support your Mac keyboard and any USB or Bluetooth gamepad with instant plug-and-play recognition.")
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 660, alignment: .leading)
            }

            Spacer(minLength: 16)

            ZStack {
                Circle()
                    .fill(SeleneTheme.ink.opacity(0.05))
                Circle()
                    .strokeBorder(SeleneTheme.ink.opacity(0.12), lineWidth: 1)
                Image(systemName: "gamecontroller.fill")
                    .seleneFont(34, .medium)
                    .foregroundColor(SeleneTheme.ink.opacity(0.72))
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Keyboard mapping

    private var mappingPanel: some View {
        SelenePanel {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader(icon: "keyboard.fill",
                            title: "Default Keyboard Mapping (Player 1)",
                            trailing: "Nintendo Switch Layout")

                panelDivider

                LazyVGrid(columns: mappingColumns, alignment: .leading, spacing: 10) {
                    VStack(spacing: 8) {
                        controlRow(badge: "LS",
                                   switchButton: "Left Stick (Move)",
                                   keyDesc: "W  A  S  D",
                                   detail: "360° Omnidirectional Movement")
                        controlRow(badge: "L3",
                                   switchButton: "Left Stick Click (L3)",
                                   keyDesc: "F",
                                   detail: "Press Left Analog Stick")
                        controlRow(badge: "R3",
                                   switchButton: "Right Stick Click (R3)",
                                   keyDesc: "G",
                                   detail: "Press Right Analog Stick")
                        controlRow(badge: "A",
                                   switchButton: "A Button (Confirm)",
                                   keyDesc: "J",
                                   detail: "Right face button (Nintendo layout)")
                        controlRow(badge: "B",
                                   switchButton: "B Button (Cancel / Jump)",
                                   keyDesc: "K",
                                   detail: "Bottom face button (Nintendo layout)")
                        controlRow(badge: "X",
                                   switchButton: "X Button (Menu / Special)",
                                   keyDesc: "U",
                                   detail: "Top face button (Nintendo layout)")
                        controlRow(badge: "Y",
                                   switchButton: "Y Button (Secondary Action)",
                                   keyDesc: "I",
                                   detail: "Left face button (Nintendo layout)")
                    }

                    VStack(spacing: 8) {
                        controlRow(badge: "L",
                                   switchButton: "Left Bumper (L)",
                                   keyDesc: "Q",
                                   detail: "Top Left Shoulder")
                        controlRow(badge: "R",
                                   switchButton: "Right Bumper (R)",
                                   keyDesc: "E",
                                   detail: "Top Right Shoulder")
                        controlRow(badge: "ZL",
                                   switchButton: "Left Trigger (ZL)",
                                   keyDesc: "Z",
                                   detail: "Analog ZL Trigger")
                        controlRow(badge: "ZR",
                                   switchButton: "Right Trigger (ZR)",
                                   keyDesc: "C",
                                   detail: "Analog ZR Trigger")
                        controlRow(badge: "D-Pad",
                                   switchButton: "Directional Pad (D-Pad)",
                                   keyDesc: "↑  ↓  ←  →",
                                   detail: "Keyboard Arrow Keys")
                        controlRow(badge: "+",
                                   switchButton: "+ Button (Plus / Start)",
                                   keyDesc: "Return (Enter)",
                                   detail: "Pause / Main Menu")
                        controlRow(badge: "−",
                                   switchButton: "− Button (Minus / Select)",
                                   keyDesc: "Tab",
                                   detail: "Map / Inventory")
                        controlRow(badge: "Shake",
                                   switchButton: "Shake Controller",
                                   keyDesc: "Spacebar",
                                   detail: "Motion Shake (Mario Galaxy / Odyssey)")
                    }
                }
            }
        }
    }

    private func controlRow(badge: String,
                            switchButton: String,
                            keyDesc: String,
                            detail: String) -> some View {
        HStack(spacing: 10) {
            Text(badge)
                .seleneFont(14, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 38, height: 38)
                .background(SeleneTheme.ink.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(switchButton)
                    .seleneFont(19, .medium)
                    .foregroundColor(SeleneTheme.ink.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(keyDesc)
                .seleneFont(14, .semibold, design: .monospaced)
                .foregroundColor(SeleneTheme.ink.opacity(0.84))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SeleneTheme.ink.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 48, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.glass.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous)
                .strokeBorder(SeleneTheme.ink15.opacity(0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Touchscreen emulation

    private var touchPanel: some View {
        SelenePanel {
            HStack(alignment: .top, spacing: 14) {
                iconTile("cursorarrow.rays")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Touchscreen Emulation (Mouse)")
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.95))

                    Text("In games featuring touch controls or pointer navigation (e.g., Captain Toad, Super Mario Galaxy, and interactive menus):")
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("Left-Click and Drag")
                            .seleneFont(14, .semibold, design: .monospaced)
                            .foregroundColor(SeleneTheme.ink.opacity(0.88))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SeleneTheme.ink.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .fixedSize()

                        Text("→ Simulates capacitive touch gestures on the Switch screen")
                            .seleneFont(15)
                            .foregroundColor(SeleneTheme.ink.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Physical gamepads

    private var gamepadPanel: some View {
        SelenePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "cable.connector")
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.7))
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    Text("Physical Gamepads & Bluetooth Controllers")
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.95))

                    Spacer(minLength: 12)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(SeleneTheme.success)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text("Plug & Play")
                            .seleneFont(14, .medium)
                            .foregroundColor(SeleneTheme.ink.opacity(0.66))
                    }
                }

                Text("Connect via Bluetooth or USB-C before or during gameplay. NX Library automatically maps standard inputs:")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 9) {
                    deviceRow("PlayStation DualSense / DualShock 4",
                              detail: "Full native haptics and analog triggers.")
                    deviceRow("Xbox Wireless Controller",
                              detail: "Immediate ABXY and trigger rumble support.")
                    deviceRow("Nintendo Switch Pro Controller",
                              detail: "Exact 1:1 button layout matching original hardware.")
                    deviceRow("Nintendo Switch Joy-Cons",
                              detail: "Supported as single horizontal pads or paired Joy-Con pair.")
                }
                .padding(.top, 2)
            }
        }
    }

    private func deviceRow(_ name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(SeleneTheme.ink.opacity(0.45))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
                .accessibilityHidden(true)

            (
                Text(name)
                    .fontWeight(.medium)
                    .foregroundColor(SeleneTheme.ink.opacity(0.88))
                + Text(": " + detail)
                    .foregroundColor(SeleneTheme.ink.opacity(0.62))
            )
            .seleneFont(15)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared pieces

    private func panelHeader(icon: String, title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.7))
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(title)
                .seleneFont(19, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.95))

            Spacer(minLength: 12)

            if let trailing {
                Text(trailing)
                    .seleneFont(14, .medium)
                    .foregroundColor(SeleneTheme.ink.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(SeleneTheme.ink15.opacity(0.9))
            .frame(height: 1)
    }

    private func iconTile(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SeleneTheme.ink.opacity(0.05))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SeleneTheme.ink.opacity(0.12), lineWidth: 1)
            Image(systemName: name)
                .seleneFont(19, .medium)
                .foregroundColor(SeleneTheme.ink.opacity(0.7))
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

// MARK: - Live controller status

private struct ControllerStatusPanel: View {
    @ObservedObject private var controller = GameControllerService.shared

    var body: some View {
        SelenePanel {
            HStack(spacing: 14) {
                statusGlyph

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(controller.isGamepadConnected
                             ? controller.activeControllerName
                             : "No Gamepad Connected")
                            .seleneFont(19, .semibold)
                            .foregroundColor(SeleneTheme.ink.opacity(0.95))
                            .lineLimit(1)

                        if controller.isGamepadConnected {
                            Text(controller.activeBrand.rawValue)
                                .seleneFont(13, .semibold)
                                .foregroundColor(SeleneTheme.ink.opacity(0.62))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(SeleneTheme.ink.opacity(0.06))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }

                    Text(controller.isGamepadConnected
                         ? "Live controller navigation across the library, detail, settings and game options."
                         : "Plug in or pair any Switch, Xbox, PlayStation or 8BitDo gamepad via Bluetooth or USB.")
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    SoundEffectService.shared.play(.click)
                    controller.refreshControllers()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .seleneFont(14, .semibold)
                        Text("Detect")
                            .seleneFont(15, .semibold)
                    }
                    .foregroundColor(SeleneTheme.ink.opacity(0.88))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Detect controller")
                .help("Scan for connected USB and Bluetooth controllers.")
            }
            .padding(.vertical, 3)
            .frame(minHeight: 48)
        }
    }

    private var statusGlyph: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(SeleneTheme.ink.opacity(0.05))
                Circle()
                    .strokeBorder(SeleneTheme.ink.opacity(0.12), lineWidth: 1)
                Image(systemName: "gamecontroller.fill")
                    .seleneFont(19, .medium)
                    .foregroundColor(SeleneTheme.ink.opacity(0.78))
            }
            .frame(width: 44, height: 44)

            Circle()
                .fill(controller.isGamepadConnected ? SeleneTheme.success : SeleneTheme.ink60)
                .frame(width: 9, height: 9)
                .overlay(
                    Circle().strokeBorder(SeleneTheme.glassSolid, lineWidth: 2)
                )
                .offset(x: 2, y: 2)
        }
        .accessibilityHidden(true)
    }
}
