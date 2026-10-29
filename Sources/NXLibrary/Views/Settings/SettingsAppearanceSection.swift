import SwiftUI
import NXLibraryCore

struct SettingsAppearanceSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void

    var body: some View {
        VStack(spacing: 9) {
            SeleneRow("Background shade",
                      subtitle: "Controls how strongly the hero artwork is dimmed behind the library.",
                      info: "Adjusts the opacity level of the background dimming scrim over the hero artwork (Subtle 30%, Balanced 55%, Deep 80%).") {
                SeleneSegmented(selection: $settings.settings.backgroundShade,
                                options: BackgroundShade.allCases.map { ($0, $0.label) })
            }

            SeleneToggleRow("Readable text",
                            subtitle: "Adds a soft halo behind hero text over bright artwork.",
                            info: "Applies subtle ambient text drop shadows so titles and tags remain crisp and legible even against high-contrast or white game hero artwork.",
                            isOn: $settings.settings.readableText)

            SeleneToggleRow("Reduce motion",
                            subtitle: "Uses fades only and removes scale or zoom transitions.",
                            isOn: $settings.settings.reduceMotion)

            SeleneToggleRow("Button hints",
                            subtitle: "Shows the keyboard and controller command bar.",
                            isOn: $settings.settings.showButtonHints)

            SeleneToggleRow("Clock",
                            subtitle: "Shows the current time in the library and settings headers.",
                            isOn: $settings.settings.showClock)

            SeleneRow("App icon",
                      subtitle: "Changes the Dock icon and the in-app brand mark.") {
                Picker("", selection: $viewModel.iconAppearanceMode) {
                    ForEach(AppIconAppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            SeleneRow("SteamGridDB API key",
                      subtitle: "Downloads transparent game logos (clear logos) on the hero stage.",
                      info: "SteamGridDB is a free community database of transparent logos and fan artwork. Create a free account at steamgriddb.com and generate an API key in Preferences → API to automatically download transparent game title logos.") {
                TextField("Optional API key", text: $settings.settings.steamGridDbApiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.glass)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SeleneTheme.ink.opacity(0.18), lineWidth: 1))
                    .cornerRadius(6)
                    .frame(width: 220)
            }
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .init(id: "shade", title: "Background shade") {
                let all = BackgroundShade.allCases
                let index = all.firstIndex(of: settings.settings.backgroundShade) ?? 0
                settings.settings.backgroundShade = all[(index + 1) % all.count]
            },
            .init(id: "readable", title: "Readable text") {
                settings.settings.readableText.toggle()
            },
            .init(id: "motion", title: "Reduce motion") {
                settings.settings.reduceMotion.toggle()
            },
            .init(id: "hints", title: "Button hints") {
                settings.settings.showButtonHints.toggle()
            },
            .init(id: "clock", title: "Clock") {
                settings.settings.showClock.toggle()
            },
            .init(id: "icon", title: "App icon") {
                let all = AppIconAppearanceMode.allCases
                let index = all.firstIndex(of: viewModel.iconAppearanceMode) ?? 0
                viewModel.iconAppearanceMode = all[(index + 1) % all.count]
            }
        ])
    }
}
