import SwiftUI
import NXLibraryCore

struct LibraryFilterBar: View {
    @Binding var selection: LibrarySelectionState
    @Binding var searchVisible: Bool
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 9) {
            Text("LB")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SeleneTheme.ink.opacity(0.62))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(SeleneTheme.ink.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            if searchVisible {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(SeleneTheme.ink.opacity(0.48))
                    TextField("Search your library", text: $selection.query.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(SeleneTheme.ink)
                        .focused(searchFocused)
                        .onSubmit { searchVisible = false }
                    Button {
                        selection.query.searchText = ""
                        searchVisible = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(SeleneTheme.ink.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close search")
                }
                .padding(.horizontal, 11)
                .frame(width: 250, height: 32)
                .background(SeleneTheme.surface.opacity(0.88))
                .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: 1))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 24) {
                    ForEach(LibraryFilter.allCases) { filter in
                        Button {
                            selection.query.filter = filter
                            selection.filterIndex = LibraryFilter.allCases.firstIndex(of: filter) ?? 0
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: selection.query.filter == filter ? .semibold : .regular))
                                .foregroundColor(selection.query.filter == filter
                                                 ? SeleneTheme.canvas
                                                 : SeleneTheme.ink.opacity(0.54))
                                .padding(.horizontal, 17)
                                .padding(.vertical, 8)
                                .background(selection.query.filter == filter
                                            ? SeleneTheme.focus
                                            : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.rawValue)
                        .accessibilityAddTraits(selection.query.filter == filter ? [.isSelected] : [])
                    }

                    Button {
                        searchVisible = true
                        searchFocused.wrappedValue = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink.opacity(0.58))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: [.command])
                    .accessibilityLabel("Search")
                }
            }

            Text("RB")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SeleneTheme.ink.opacity(0.62))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(SeleneTheme.ink.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(SeleneTheme.canvas.opacity(0.18))
        .clipShape(Capsule())
    }
}
