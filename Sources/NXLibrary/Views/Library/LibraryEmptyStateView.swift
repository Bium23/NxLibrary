import SwiftUI

struct LibraryEmptyStateView: View {
    let onAdd: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Your library is empty")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-1.1)
                .foregroundColor(SeleneTheme.ink)

            Text("Add a game to start your collection.")
                .font(.system(size: 14))
                .foregroundColor(SeleneTheme.inkMuted)

            HStack(spacing: 22) {
                Button(action: onAdd) {
                    Text("Add a game")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SeleneTheme.canvas)
                        .padding(.horizontal, 26)
                        .frame(height: 44)
                        .background(SeleneTheme.focus)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onImport) {
                    Text("Import existing builds")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SeleneTheme.ink.opacity(0.66))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
