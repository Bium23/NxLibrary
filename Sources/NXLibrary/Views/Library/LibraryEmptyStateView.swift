import SwiftUI

struct LibraryEmptyStateView: View {
    let onAdd: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(SeleneTheme.accent.opacity(0.55))

            VStack(spacing: 5) {
                Text("Your library is empty")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink)
                Text("Add a game or import an existing nxnative build.")
                    .font(.system(size: 12))
                    .foregroundColor(SeleneTheme.inkMuted)
            }

            HStack(spacing: 10) {
                Button(action: onAdd) {
                    Text("Add a game")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SeleneTheme.canvas)
                        .padding(.horizontal, 22)
                        .frame(height: 40)
                        .background(SeleneTheme.focus)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onImport) {
                    Text("Import existing builds")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink.opacity(0.8))
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .background(SeleneTheme.ink.opacity(0.08))
                        .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
