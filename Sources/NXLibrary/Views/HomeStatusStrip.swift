import SwiftUI

public struct HomeStatusStrip: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            Label("\(viewModel.libraryGames.count) game\(viewModel.libraryGames.count == 1 ? "" : "s")",
                  systemImage: "square.grid.2x2.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(NXTheme.textSecondary)

            divider
            indicator("Keys", ok: viewModel.isProdKeysValid,
                      help: viewModel.isProdKeysValid
                        ? "prod.keys is imported and validated."
                        : "Import prod.keys in Settings.")
            divider
            indicator("Engine", ok: viewModel.isNxnativeValid,
                      help: viewModel.isNxnativeValid
                        ? "nxnative is available at the pinned checkout."
                        : "Choose the nxnative checkout in Settings.")
            divider
            indicator("Toolchain", ok: viewModel.compatibilityReport?.ok == true,
                      override: viewModel.allowUntestedToolchain,
                      help: toolchainHelp)

            Spacer()

            if viewModel.isBuilding {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.currentStageName.isEmpty ? "Building..." : viewModel.currentStageName)
                        .lineLimit(1)
                    Text("\(Int(viewModel.progressFraction * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(NXTheme.textPrimary)
            } else {
                Text(viewModel.canPassToolchainGate ? "Ready" : (viewModel.compatibilityReport == nil ? "Checking toolchain" : "Builds blocked"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((viewModel.canPassToolchainGate ? NXTheme.success : NXTheme.warning)
                        .opacity(0.14))
                    .foregroundColor(viewModel.canPassToolchainGate ? NXTheme.success : NXTheme.warning)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NXTheme.glassSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NXTheme.borderSubtle.opacity(0.55), lineWidth: 0.8)
        )
        .shadow(color: NXTheme.cardShadow.opacity(0.45), radius: 10, x: 0, y: 3)
    }

    private var divider: some View {
        Rectangle()
            .fill(NXTheme.borderSubtle)
            .frame(width: 1, height: 12)
    }

    private func indicator(_ title: String, ok: Bool, override: Bool = false,
                           help: String) -> some View {
        let color = ok ? NXTheme.success : (override ? NXTheme.warning : NXTheme.error)
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(NXTheme.textSecondary)
        }
        .help(help)
    }

    private var toolchainHelp: String {
        if viewModel.compatibilityReport?.ok == true {
            return "Engine commit, Metal compiler and CLI match the certified combination."
        }
        let blocked = viewModel.compatibilityReport?.checks
            .filter { $0.status == .block }
            .map { "\($0.title): \($0.detail)" }
            .joined(separator: " | ")
        return blocked?.isEmpty == false
            ? "Toolchain blocked: \(blocked!)"
            : "The toolchain check is still running or unavailable."
    }
}
