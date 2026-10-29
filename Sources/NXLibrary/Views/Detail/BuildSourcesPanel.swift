import SwiftUI
import NXLibraryCore

struct BuildSourcesPanel: View {
    let presentation: GameDetailPresentation
    var isRebuildFocused: Bool = false
    let onAttach: () -> Void
    let onRebuild: () -> Void
    let onRevealLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Build & sources")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundColor(SeleneTheme.ink60)
                SeleneInfoTip("NX Library uses symlinks to your game ROM files to build the macOS native binary. Rebuilding uses your current engine pin and settings, and preserves your game saves.")
                Spacer()
                if presentation.sourcesDetached {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SeleneTheme.untested)
                            .frame(width: 5, height: 5)
                        Text("Sources detached")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SeleneTheme.untested.opacity(0.86))
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SeleneTheme.success)
                            .frame(width: 5, height: 5)
                        Text("Sources attached")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SeleneTheme.success.opacity(0.86))
                    }
                }
            }

            Text(presentation.sourcesDetached
                 ? "The installed app is playable. A rebuild needs the original XCI/NSP files; attach them again without touching saves."
                 : "The original sources are attached. Rebuild writes a new app and keeps the previous one if it fails.")
                .font(.system(size: 11))
                .foregroundColor(SeleneTheme.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onAttach) {
                    Text("Attach sources…")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink.opacity(0.86))
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(SeleneTheme.ink.opacity(0.08))
                        .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.14), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onRebuild) {
                    Text("Rebuild")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(presentation.canRebuild ? SeleneTheme.scrim : SeleneTheme.ink60)
                        .padding(.horizontal, 15)
                        .frame(height: 32)
                        .background(presentation.canRebuild ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.07))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!presentation.canRebuild)
                .seleneCapsuleFocus(isRebuildFocused)

                Button(action: onRevealLog) {
                    Text("Open log")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.glyph)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Engine \(presentation.engineCommitShort)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(SeleneTheme.ink.opacity(0.64))
                    Text(presentation.toolchainVerified ? "Certified" : "Untested toolchain")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(presentation.toolchainVerified
                                         ? SeleneTheme.success.opacity(0.8)
                                         : SeleneTheme.untested.opacity(0.8))
                }
            }
        }
        .padding(16)
        .background(SeleneTheme.glass.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
    }
}
