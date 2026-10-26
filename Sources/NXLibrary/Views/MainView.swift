import SwiftUI

public struct MainView: View {
    @StateObject private var viewModel = AppViewModel()

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.nxCanvas.ignoresSafeArea()

                ZStack {
                    Circle()
                        .fill(NXTheme.primary.opacity(0.13))
                        .frame(width: 460, height: 460)
                        .blur(radius: 100)
                        .position(x: 90, y: 30)

                    Circle()
                        .fill(NXTheme.secondary.opacity(0.06))
                        .frame(width: 420, height: 420)
                        .blur(radius: 110)
                        .position(x: geo.size.width - 60, y: geo.size.height - 40)
                }
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
            return "Toolchain blocked"
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
                    .foregroundColor(NXTheme.textSecondary)
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
        .background(
            ZStack {
                NXTheme.canvasObsidian.opacity(0.86)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(NXTheme.borderSubtle),
            alignment: .bottom
        )
    }
}
