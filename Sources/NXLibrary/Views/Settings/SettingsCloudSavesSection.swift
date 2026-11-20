import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Porting → Cloud saves: one save-sync choice for every ported game, applied at its next launch.
struct SettingsCloudSavesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var cloudSaves: CloudSaves { settings.settings.cloudSaves }

    private var pickedFolderSubtitle: String {
        let picked = settings.settings.cloudSavesPickedFolder
        return picked.isEmpty ? L10n.text("None chosen yet.") : (picked as NSString).abbreviatingWithTildeInPath
    }

    private func stepCloudSaves(_ step: Int) {
        viewModel.setCloudSaves(cloudSaves.stepped(step, picked: settings.settings.cloudSavesPickedFolder))
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SeleneCycleRow("Cloud saves",
                           subtitle: "All games · Next launch",
                           info: "Applied before each game starts, including Off. Custom save-sync overrides are reported in Saves. Cloud sync covers only the primary user and device save.",
                           value: cloudSaves.title, cycle: stepCloudSaves)

            SeleneButtonRow("Cloud saves folder",
                            subtitle: pickedFolderSubtitle,
                            buttonTitle: "Choose…") { viewModel.chooseCloudSavesFolder() }

        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .value("cloudSaves", "Cloud saves", cycle: stepCloudSaves),
            .init(id: "cloudSavesFolder", title: "Cloud saves folder") { viewModel.chooseCloudSavesFolder() }
        ])
    }
}
