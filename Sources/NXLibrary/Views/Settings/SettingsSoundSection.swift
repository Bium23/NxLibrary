import SwiftUI
import AppKit
import NXLibraryCore

struct SettingsSoundSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @State private var importNote: String?

    private func stepVolume(_ step: Int) {
        let next = (settings.settings.soundVolume * 10).rounded() + Double(step)
        settings.settings.soundVolume = min(10, max(0, next)) / 10
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SeleneToggleRow("Interface sounds",
                            subtitle: "Plays a short sound when you move, select, go back or launch a game.",
                            isOn: $settings.settings.interfaceSounds)

            SeleneRow("Sound volume", subtitle: "How loud the interface sounds are.") {
                HStack(spacing: canvas.u(12)) {
                    Slider(value: $settings.settings.soundVolume, in: 0...1, step: 0.05)
                        .frame(width: canvas.u(220))
                    SeleneValueChip(text: "\(Int((settings.settings.soundVolume * 100).rounded()))%")
                }
            }

            SeleneToggleRow("Quiet launch screen",
                            subtitle: "Keeps the launch screen silent while a game starts.",
                            isOn: $settings.settings.quietLaunch)

            SettingsSubheading("Selene")

            SeleneButtonRow("Import sounds and wallpapers from Selene",
                            subtitle: importNote
                                ?? "Copies optional sounds and wallpapers from a local Selene folder you own.",
                            buttonTitle: "Choose folder") { importFromSelene() }
        }
        .onAppear(perform: publishActions)
        .onChange(of: settings.settings.interfaceSounds) { enabled in
            if enabled { SoundEffectService.shared.play(.key) }
        }
    }

    private func publishActions() {
        onActions([
            .init(id: "sounds", title: "Interface sounds") {
                settings.settings.interfaceSounds.toggle()
            },
            .value("volume", "Sound volume") { stepVolume($0) },
            .init(id: "quietLaunch", title: "Quiet launch screen") {
                settings.settings.quietLaunch.toggle()
            },
            .init(id: "importSelene", title: "Import sounds and wallpapers from Selene") {
                importFromSelene()
            }
        ])
    }

    private func importFromSelene() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose your Selene folder (the one that contains theme/theme.yaml)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = try SeleneImporter().importFrom(seleneRoot: url)
            SoundEffectService.shared.reloadSounds()
            NotificationCenter.default.post(name: .nxSeleneImportFinished, object: nil)
            importNote = "Imported \(report.copied.count) files"
                + (report.missing.isEmpty ? "." : "; \(report.missing.count) not found in that folder.")
            SoundEffectService.shared.play(.success)
        } catch {
            importNote = error.localizedDescription
            SoundEffectService.shared.play(.alert)
        }
    }
}

extension Notification.Name {
    /// Posted after a Selene import so wallpaper lists reload.
    static let nxSeleneImportFinished = Notification.Name("nxSeleneImportFinished")
}
