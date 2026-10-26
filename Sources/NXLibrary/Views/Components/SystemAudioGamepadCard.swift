import SwiftUI

public struct SystemAudioGamepadCard: View {
    @ObservedObject public var viewModel: AppViewModel
    @ObservedObject private var soundService = SoundEffectService.shared
    @ObservedObject private var controllerService = GameControllerService.shared
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Gamepad & Audio Experience", systemImage: "gamecontroller.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                    
                    Spacer()
                    
                    Text(controllerService.isGamepadConnected ? "Controller Connected" : "No Controller Detected")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(controllerService.isGamepadConnected ? NXTheme.success.opacity(0.2) : NXTheme.glassSurfaceElevated)
                        .foregroundColor(controllerService.isGamepadConnected ? NXTheme.success : NXTheme.textMuted)
                        .clipShape(Capsule())
                }
                
                Divider().opacity(0.2)
                
                // Gamepad Info Row
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Gamepad Device")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(NXTheme.textPrimary)
                        Text(controllerService.activeControllerName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(NXTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button("View Button Layout") {
                        SoundEffectService.shared.play(.click)
                        viewModel.selectedTab = 2 // Controls tab
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                }
                
                Divider().opacity(0.15)

                // Navigation deadzone
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stick Navigation Deadzone")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(NXTheme.textPrimary)
                        Text("How far the left stick must move before the library focus changes.")
                            .font(.system(size: 10))
                            .foregroundColor(NXTheme.textSecondary)
                    }

                    Spacer()

                    Slider(value: Binding(
                        get: { Double(controllerService.deadzone) },
                        set: { controllerService.deadzone = Float($0) }
                    ), in: 0.10...0.60)
                    .frame(width: 160)
                    .tint(NXTheme.primary)

                    Text(String(format: "%.2f", controllerService.deadzone))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(NXTheme.secondary)
                        .frame(width: 34, alignment: .trailing)
                }

                Divider().opacity(0.15)
                
                // Audio Toggle Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Console UI Sound Effects")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(NXTheme.textPrimary)
                        Text("Play short synthesized feedback tones when clicking buttons, navigating tabs, and launching games.")
                            .font(.system(size: 10))
                            .foregroundColor(NXTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $soundService.isSoundEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: soundService.isSoundEnabled) { val in
                            if val {
                                SoundEffectService.shared.play(.click)
                            }
                        }
                }
            }
        }
    }
}
