import SwiftUI
import NXLibraryCore

struct SettingsGamesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var languageOptions: [(code: String, label: String)] {
        var options = viewModel.availableLanguages
        let current = settings.settings.gameDefaults.language
        if !options.contains(where: { $0.code == current }) {
            options.append((current, current.isEmpty ? "Game Default" : current))
        }
        return options
    }

    private var surprisePoolTitle: String {
        switch settings.settings.surprisePool {
        case .installed: return "Installed"
        case .notPlayed: return "Not played yet"
        case .all: return "All games"
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading("Launch screen")

            SeleneCycleRow("Launch screen style",
                           subtitle: "What shows while a game starts.",
                           value: settings.settings.launchStyle.title) { step in
                settings.settings.launchStyle = settings.settings.launchStyle.stepped(step)
            }

            SeleneToggleRow("Launch screen motion",
                            subtitle: "A slow drift of the art while the game starts.",
                            isOn: $settings.settings.launchMotion)

            SeleneCycleRow("Launch screen shade",
                           subtitle: "How much the launch art is darkened.",
                           value: settings.settings.launchShade.title) { step in
                settings.settings.launchShade = settings.settings.launchShade.stepped(step)
            }

            SeleneCycleRow("Surprise me pool",
                           subtitle: "Which games Surprise me picks from.",
                           value: surprisePoolTitle) { step in
                settings.settings.surprisePool = settings.settings.surprisePool.stepped(step)
            }

            SettingsSubheading("Game defaults")

            SeleneToggleRow("Fullscreen",
                            subtitle: "Start newly added games in fullscreen.",
                            isOn: $settings.settings.gameDefaults.fullscreen)

            SeleneToggleRow("60 FPS",
                            subtitle: "Target 60 frames per second instead of 30.",
                            info: "Some games tie their physics, animation speeds, or game loops to 30 FPS. If gameplay runs twice as fast or audio desyncs, keep this at 30.",
                            isOn: $settings.settings.gameDefaults.enable60FPS)

            SeleneToggleRow("Docked mode",
                            subtitle: "Use the docked performance profile for new games.",
                            info: "Simulates the Nintendo Switch docked TV profile (1080p target, higher clocks and memory limits). Disabling uses handheld profile (720p target, lower GPU load).",
                            isOn: $settings.settings.gameDefaults.isDockedMode)

            SeleneToggleRow("MetalFX spatial upscaling",
                            subtitle: "Enable the engine's MetalFX present upscale.",
                            info: "Uses Apple MetalFX Spatial Upscaling to upscale lower internal render targets to display resolution with edge sharpening, without raising GPU raster load.",
                            isOn: $settings.settings.gameDefaults.enableMetalFXUpscale)

            SeleneToggleRow("Metal HUD",
                            subtitle: "Show the Metal performance overlay in new games.",
                            info: "Displays Apple's official Metal Performance HUD overlay during gameplay showing real-time frame rates, frame time graphs, and GPU utilization.",
                            isOn: $settings.settings.gameDefaults.enableMetalHUD)

            SeleneRow("Default game language",
                      subtitle: "Game Default lets each title use the language in its own metadata.") {
                Picker("", selection: $settings.settings.gameDefaults.language) {
                    ForEach(languageOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            SeleneRow("Render scale",
                      info: "Scales the internal 3D rendering buffer relative to native target (50% to 100%). Lowering this reduces GPU heat on battery; UI remains full resolution.") {
                HStack(spacing: 10) {
                    Slider(value: $settings.settings.gameDefaults.renderScale,
                           in: 0.5...1.0, step: 0.05)
                        .frame(width: 170)
                    Text("\(Int((settings.settings.gameDefaults.renderScale * 100).rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.glyph)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            SelenePanel("Resolution") {
                Text("Output follows the window or display. Render scale changes the internal 3D resolution only; native 1440p/4K is not available in this engine pin.")
                    .font(.system(size: 11))
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Changing these defaults does not modify games already in the library.")
                .font(.system(size: 10))
                .foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .value("launchStyle", "Launch screen style") { step in
                settings.settings.launchStyle = settings.settings.launchStyle.stepped(step)
            },
            .init(id: "launchMotion", title: "Launch screen motion") {
                settings.settings.launchMotion.toggle()
            },
            .value("launchShade", "Launch screen shade") { step in
                settings.settings.launchShade = settings.settings.launchShade.stepped(step)
            },
            .value("surprisePool", "Surprise me pool") { step in
                settings.settings.surprisePool = settings.settings.surprisePool.stepped(step)
            },
            .init(id: "fullscreen", title: "Fullscreen") {
                settings.settings.gameDefaults.fullscreen.toggle()
            },
            .init(id: "fps", title: "60 FPS") {
                settings.settings.gameDefaults.enable60FPS.toggle()
            },
            .init(id: "docked", title: "Docked mode") {
                settings.settings.gameDefaults.isDockedMode.toggle()
            },
            .init(id: "metalfx", title: "MetalFX spatial upscaling") {
                settings.settings.gameDefaults.enableMetalFXUpscale.toggle()
            },
            .init(id: "hud", title: "Metal HUD") {
                settings.settings.gameDefaults.enableMetalHUD.toggle()
            },
            .value("language", "Default game language") { step in
                let codes = languageOptions.map(\.code)
                if let next = codes.stepped(from: settings.settings.gameDefaults.language, step) {
                    settings.settings.gameDefaults.language = next
                }
            },
            .value("scale", "Render scale") { step in
                let values = stride(from: 0.5, through: 1.0, by: 0.05).map { $0 }
                let current = settings.settings.gameDefaults.renderScale
                let index = values.firstIndex { abs($0 - current) < 0.001 } ?? values.count - 1
                settings.settings.gameDefaults.renderScale = values[min(max(index + step, 0), values.count - 1)]
            }
        ])
    }
}
