import SwiftUI
import NXLibraryCore

public struct SystemView: View {
    @ObservedObject public var viewModel: AppViewModel
    @State private var selectedSection: SettingsSection = .keys

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public enum SettingsSection: String, CaseIterable, Identifiable {
        case keys = "Keys"
        case storage = "Storage"
        case engine = "Engine"
        case controls = "Controls"
        case appearance = "Appearance"
        case about = "About"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .keys: return "key.fill"
            case .storage: return "externaldrive.fill"
            case .engine: return "cpu.fill"
            case .controls: return "gamecontroller.fill"
            case .appearance: return "paintpalette.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            sectionBar
            ScrollView {
                content
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .keys:
            VStack(spacing: 12) {
                SystemKeysCard(viewModel: viewModel)
                infoCard(
                    "Key handling",
                    text: "The key file is copied once to Application Support/NXLibrary/keys with mode 0600. The app never displays or logs key values."
                )
            }
        case .storage:
            VStack(spacing: 12) {
                StorageCard(viewModel: viewModel)
                SystemDirectoriesCard(viewModel: viewModel)
            }
        case .engine:
            VStack(spacing: 12) {
                SystemRepoCard(viewModel: viewModel)
                CompatibilityCard(viewModel: viewModel)
                UpstreamCard(viewModel: viewModel)
                SystemToolsCard(viewModel: viewModel)
            }
        case .controls:
            VStack(spacing: 12) {
                ControllerLiveStatusCard()
                SystemAudioGamepadCard(viewModel: viewModel)
            }
        case .appearance:
            SystemAppearanceCard(viewModel: viewModel)
        case .about:
            VStack(spacing: 12) {
                SystemCreditsCard()
                infoCard(
                    "About NX Library",
                    text: "NX Library is a personal tool for building and launching your own Switch games on this Mac. It is not affiliated with Nintendo. No Nintendo logos, fonts, sounds or UI assets are included; the engine is nxnative (MIT)."
                )
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text("Keys, storage, engine gate, controls and appearance.")
                    .font(.system(size: 12))
                    .foregroundColor(NXTheme.textSecondary)
            }

            Spacer()

            Button("Setup") {
                SoundEffectService.shared.play(.click)
                viewModel.reopenSetup()
            }
            .buttonStyle(NXSecondaryButtonStyle())

            Button(action: {
                SoundEffectService.shared.play(.click)
                viewModel.detectEnvironment()
            }) {
                HStack(spacing: 6) {
                    if viewModel.isCheckingPrerequisites {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-check")
                    }
                }
            }
            .buttonStyle(NXSecondaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            ZStack {
                NXTheme.canvasObsidian.opacity(0.6)
                Rectangle().fill(NXTheme.barGradient)
            }
        )
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(NXTheme.borderSubtle),
            alignment: .bottom
        )
    }

    private var sectionBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(SettingsSection.allCases.enumerated()), id: \.element) { index, section in
                let isSelected = selectedSection == section
                Button {
                    SoundEffectService.shared.play(.tabSwitch)
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium,
                                          design: .rounded))
                    }
                    .foregroundColor(isSelected ? NXTheme.primary : NXTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? NXTheme.primary.opacity(0.13) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .nxNoFocusRing()
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(NXTheme.glassSurface.opacity(0.5))
    }

    private func infoCard(_ title: String, text: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
