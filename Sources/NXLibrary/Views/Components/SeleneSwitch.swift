import SwiftUI

struct SeleneSwitch: View {
    @Environment(\.seleneCanvas) private var canvas
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            SoundEffectService.shared.play(.key)
        } label: {
            Capsule()
                .fill(isOn ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.13))
                .frame(width: canvas.u(56), height: canvas.u(30))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? SeleneTheme.onFocus : SeleneTheme.ink)
                        .frame(width: canvas.u(22), height: canvas.u(22))
                        .padding(canvas.u(4))
                }
        }
        .buttonStyle(.plain)
        .animation(SeleneTheme.quick, value: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}
