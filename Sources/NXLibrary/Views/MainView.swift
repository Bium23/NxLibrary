import SwiftUI

public struct MainView: View {
    @StateObject private var viewModel = AppViewModel()

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [NXTheme.canvasObsidian, NXTheme.canvasLift, NXTheme.canvasObsidian],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ZStack {
                    Circle()
                        .fill(NXTheme.primary.opacity(0.10))
                        .frame(width: 560, height: 560)
                        .blur(radius: 130)
                        .position(x: 60, y: -40)

                    Circle()
                        .fill(NXTheme.secondary.opacity(0.08))
                        .frame(width: 520, height: 520)
                        .blur(radius: 140)
                        .position(x: geo.size.width - 40, y: geo.size.height * 0.12)

                    Circle()
                        .fill(NXTheme.ambientIndigo.opacity(0.06))
                        .frame(width: 620, height: 620)
                        .blur(radius: 160)
                        .position(x: geo.size.width * 0.52, y: geo.size.height + 120)
                }
                .ignoresSafeArea()

                LinearGradient(
                    colors: [Color.clear, NXTheme.canvasObsidian.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    BottomDock(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .sheet(isPresented: $viewModel.showSetupSheet) {
            SetupView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryPlayFocused)) { _ in
            guard viewModel.selectedTab == 0,
                  let game = viewModel.currentFocusedGame else { return }
            viewModel.launchGame(game)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryCheckUpstream)) { _ in
            viewModel.checkUpstreamChangelog()
        }
        .alert("NX Library", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var content: some View {
        Group {
            switch viewModel.selectedTab {
            case 0:
                LibraryView(viewModel: viewModel)
            case 1:
                BuildView(viewModel: viewModel)
            case 2:
                ControlsView()
            case 3:
                SystemView(viewModel: viewModel)
            case 4:
                LogsView(viewModel: viewModel)
            default:
                LibraryView(viewModel: viewModel)
            }
        }
    }

    private var readiness: Bool {
        viewModel.isProdKeysValid
            && viewModel.isNxnativeValid
            && viewModel.environmentStatus?.canBuild == true
            && viewModel.canPassToolchainGate
    }

    private var readinessText: String {
        if readiness { return "Ready" }
        if viewModel.compatibilityReport != nil && !viewModel.canPassToolchainGate {
            return "Builds blocked"
        }
        return "Setup needed"
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            AppLogoView(viewModel: viewModel)

            VStack(alignment: .leading, spacing: 1) {
                Text("NX Library")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text("Native Switch games on Mac")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.2)
                    .foregroundColor(NXTheme.textMuted)
            }

            Spacer()

            if viewModel.isBuilding {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.currentStageName.isEmpty ? "Building..." : viewModel.currentStageName)
                        .lineLimit(1)
                    Text("\(Int(viewModel.progressFraction * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(NXTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NXTheme.primary.opacity(0.16))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(NXTheme.primary.opacity(0.4), lineWidth: 0.8))
            } else {
                if viewModel.allowUntestedToolchain && viewModel.compatibilityReport?.ok != true {
                    Text("Untested toolchain")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NXTheme.warning.opacity(0.12))
                        .clipShape(Capsule())
                }
                StatusBadge(
                    isPositive: readiness,
                    text: readinessText,
                    showText: true
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(height: 56)
        .background(NXTheme.barGradient)
        .overlay(
            LinearGradient(
                colors: [
                    NXTheme.primary.opacity(0.35),
                    NXTheme.secondary.opacity(0.18),
                    NXTheme.borderSubtle.opacity(0.35)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1),
            alignment: .bottom
        )
    }
}
