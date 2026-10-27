import SwiftUI
import NXLibraryCore

public struct SetupView: View {
    @ObservedObject public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            NXTheme.canvasObsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        environmentCard
                        SystemKeysCard(viewModel: viewModel)
                        foldersCard
                        importCard
                        toolchainNotice
                    }
                    .padding(20)
                }
                footer
            }
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 700, idealHeight: 780)
        .onAppear {
            viewModel.detectEnvironment()
            if viewModel.importedApps.isEmpty {
                viewModel.importExistingBuilds()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NXTheme.primary.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 22))
                    .foregroundColor(NXTheme.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to NX Library")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text("Four checks before the library opens. Nothing is installed or changed automatically.")
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
            }

            Spacer()

            Button("Not Now") {
                viewModel.showSetupSheet = false
                dismiss()
            }
            .buttonStyle(NXSecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .background(
            ZStack {
                NXTheme.glassSurfaceElevated.opacity(0.7)
                Rectangle().fill(NXTheme.barGradient)
            }
        )
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(NXTheme.borderSubtle),
            alignment: .bottom
        )
    }

    private var environmentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                setupHeader("1. Build environment", icon: "wrench.and.screwdriver.fill",
                            ok: viewModel.environmentStatus?.canBuild == true)

                if let environment = viewModel.environmentStatus {
                    HStack(spacing: 12) {
                        summaryCell("Xcode", environment.xcodeVersion ?? "missing")
                        summaryCell("Metal", environment.metalVersion ?? "missing")
                        summaryCell("venv", environment.pythonURL?.lastPathComponent ?? "missing")
                    }
                    if !environment.issues.isEmpty {
                        Text(environment.issues.joined(separator: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(NXTheme.warning)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking the nxnative toolchain...")
                            .font(.system(size: 11))
                            .foregroundColor(NXTheme.textSecondary)
                    }
                }

                HStack {
                    Text("The nxnative checkout is used in place at \(viewModel.nxnativePath).")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textMuted)
                    Spacer()
                    Button("Re-check") { viewModel.detectEnvironment() }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .controlSize(.small)
                }
            }
        }
    }

    private var foldersCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                setupHeader("3. Folders", icon: "folder.fill", ok: viewModel.libraryFolder != nil)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App library")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(NXTheme.textPrimary)
                        Text(viewModel.libraryFolder?.path ?? "~/Applications")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(NXTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change...") { viewModel.selectLibraryFolder() }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .controlSize(.small)
                }
                .padding(8)
                .background(NXTheme.glassSurfaceElevated.opacity(0.45))
                .cornerRadius(8)

                Text("Built apps are installed in ~/Applications. Game sources are referenced where they are; they are never copied into the app.")
                    .font(.system(size: 10))
                    .foregroundColor(NXTheme.textMuted)
            }
        }
    }

    private var importCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                setupHeader("4. Import existing builds", icon: "square.and.arrow.down.fill",
                            ok: !viewModel.importedApps.isEmpty)

                if viewModel.isScanningLibrary {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning ~/Applications...")
                            .font(.system(size: 11))
                            .foregroundColor(NXTheme.textSecondary)
                    }
                } else if viewModel.importedApps.isEmpty {
                    Text("No nxnative app found yet. You can add games later from Add Game.")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.textSecondary)
                } else {
                    ForEach(viewModel.importedApps) { app in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(NXTheme.success)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(NXTheme.textPrimary)
                                Text("\(app.titleId ?? "no title ID") · v\(app.version ?? "?") · \(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(NXTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(NXTheme.glassSurfaceElevated.opacity(0.4))
                        .cornerRadius(6)
                    }
                }

                HStack {
                    Text("Imported apps are playable immediately; rebuilds need their source files.")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textMuted)
                    Spacer()
                    Button("Scan Again") { viewModel.importExistingBuilds() }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var toolchainNotice: some View {
        if let report = viewModel.compatibilityReport, !report.ok {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(NXTheme.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text("New builds are blocked by the toolchain gate")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(NXTheme.warning)
                    Text("You can still finish setup and play imported games. Review the engine and Metal compatibility in Settings before building.")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textSecondary)
                    Button("Review in Settings") {
                        viewModel.selectedTab = 3
                        viewModel.showSetupSheet = false
                        dismiss()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(10)
            .background(NXTheme.warning.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(NXTheme.warning.opacity(0.25), lineWidth: 0.8)
            )
        }
    }

    private var footer: some View {
        HStack {
            Text(viewModel.canCompleteSetup
                 ? "Setup checks passed."
                 : setupHint)
                .font(.system(size: 11))
                .foregroundColor(viewModel.canCompleteSetup ? NXTheme.success : NXTheme.warning)

            Spacer()

            Button("Finish Setup") {
                viewModel.completeSetup()
                dismiss()
            }
            .buttonStyle(NXPrimaryButtonStyle())
            .disabled(!viewModel.canCompleteSetup)
            .opacity(viewModel.canCompleteSetup ? 1 : 0.45)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
        .background(
            ZStack {
                NXTheme.glassSurfaceElevated.opacity(0.7)
                Rectangle().fill(NXTheme.barGradient)
            }
        )
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(NXTheme.borderSubtle),
            alignment: .top
        )
    }

    private var setupHint: String {
        if !viewModel.isNxnativeValid { return "The nxnative checkout is missing." }
        if !viewModel.isProdKeysValid { return "Import a valid prod.keys file." }
        if viewModel.environmentStatus?.canBuild != true { return "The build environment is incomplete." }
        if viewModel.libraryFolder == nil { return "Choose an app library folder." }
        return "Complete the checks above to continue."
    }

    private func setupHeader(_ title: String, icon: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(NXTheme.primary)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(NXTheme.textPrimary)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ok ? NXTheme.success : NXTheme.textMuted)
        }
    }

    private func summaryCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(NXTheme.textMuted)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(NXTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(NXTheme.glassSurfaceElevated.opacity(0.45))
        .cornerRadius(6)
    }
}
