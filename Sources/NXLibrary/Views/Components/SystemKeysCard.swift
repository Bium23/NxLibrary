import SwiftUI

public struct SystemKeysCard: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Decryption Keys (prod.keys)", systemImage: "key.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                        .help("The key file is copied once into Application Support, mode 0600. Values are never shown or logged.")

                    Spacer()

                    StatusBadge(
                        isPositive: viewModel.isProdKeysValid,
                        text: viewModel.isProdKeysValid ? "Keys OK" : "Keys missing"
                    )
                }

                HStack(spacing: 8) {
                    HStack {
                        if viewModel.isProdKeysValid && !viewModel.prodKeysPath.isEmpty {
                            Text(viewModel.prodKeysPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(NXTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No prod.keys imported yet. Choose your file once.")
                                .font(.system(size: 12))
                                .foregroundColor(NXTheme.textSecondary)
                        }
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

                    Button(viewModel.isProdKeysValid ? "Replace Key..." : "Import Key...") {
                        viewModel.selectProdKeysFile()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())

                    Button("Detect Ryujinx...") {
                        viewModel.selectRyujinxFolder()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                }

                if let summary = viewModel.keySummary {
                    HStack(spacing: 10) {
                        Text("header_key present")
                            .foregroundColor(NXTheme.success)
                        Text("·")
                            .foregroundColor(NXTheme.textMuted)
                        Text("\(summary.applicationKeyGenerations.count) application key generations")
                            .foregroundColor(NXTheme.textSecondary)
                    }
                    .font(.system(size: 10, design: .monospaced))
                }

                Text("Your original file is untouched. The stored copy is used by nxnative and is never logged.")
                    .font(.system(size: 10))
                    .foregroundColor(NXTheme.textMuted)
            }
        }
    }
}
