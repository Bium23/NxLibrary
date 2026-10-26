import SwiftUI

public struct SystemRepoCard: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Core Repository (nxnative)", systemImage: "folder.badge.gearshape")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                        .help("The upstream conversion scripts and headers from seedds/nxnative required to compile native ports.")

                    Spacer()

                    StatusBadge(
                        isPositive: viewModel.isNxnativeValid,
                        text: viewModel.isNxnativeValid ? "Installed and Ready" : "Repository Missing"
                    )
                }

                HStack(spacing: 8) {
                    HStack {
                        Text(viewModel.nxnativePath.isEmpty ? "Select the ~/nxnative folder..." : viewModel.nxnativePath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(viewModel.nxnativePath.isEmpty ? NXTheme.textSecondary : NXTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(NXTheme.glassSurfaceElevated)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(NXTheme.specularRim, lineWidth: 0.8)
                    )

                    Button("Change...") {
                        viewModel.selectNxnativeFolder()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                }

                Divider().opacity(0.2)

                Text("Pinned engine: 06b7b3e")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(NXTheme.textMuted)
                Text("Updates are manual; the app never changes the engine checkout.")
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
            }
        }
    }
}
