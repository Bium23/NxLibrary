import SwiftUI
import NXLibraryCore

public struct SystemToolsCard: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Build Environment", systemImage: "wrench.and.screwdriver.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)

                    Spacer()

                    if let status = viewModel.environmentStatus {
                        Text(status.canBuild ? "Ready" : "Incomplete")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(status.canBuild ? NXTheme.success : NXTheme.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((status.canBuild ? NXTheme.success : NXTheme.warning).opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        ProgressView().controlSize(.small)
                    }

                    Button("Re-check") {
                        viewModel.refreshCompatibility()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                }

                if let status = viewModel.environmentStatus {
                    VStack(spacing: 6) {
                        toolRow("Xcode", ok: status.xcodeVersion != nil,
                                detail: status.xcodeVersion ?? "not found")
                        toolRow("Metal compiler", ok: status.metalVersion != nil,
                                detail: status.metalVersion ?? "not found")
                        toolRow("nxnative venv", ok: !status.issues.contains {
                            $0.lowercased().contains("venv")
                        }, detail: status.pythonURL?.path ?? "missing")
                        toolRow(".NET 10 runtime", ok: !status.issues.contains {
                            $0.lowercased().contains(".net")
                        }, detail: "checked by the build command")
                        ForEach(status.tools) { tool in
                            toolRow(tool.name, ok: tool.ok, detail: tool.detail)
                        }
                    }

                    if !status.issues.isEmpty {
                        Text(status.issues.joined(separator: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(NXTheme.warning)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NXTheme.warning.opacity(0.09))
                            .cornerRadius(8)
                    }
                } else {
                    Text("Checking the build environment...")
                        .font(.system(size: 11))
                        .foregroundColor(NXTheme.textSecondary)
                }
            }
        }
    }

    private func toolRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ok ? NXTheme.success : NXTheme.error)
                .frame(width: 15)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NXTheme.textPrimary)
                .frame(width: 112, alignment: .leading)
            Text(detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(NXTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NXTheme.glassSurfaceElevated.opacity(0.45))
        .cornerRadius(6)
    }
}
