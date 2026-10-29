import SwiftUI
import NXLibraryCore

struct LibraryFilterBar: View {
    @Binding var selection: LibrarySelectionState
    @Binding var searchVisible: Bool
    var searchFocused: FocusState<Bool>.Binding
    let showButtonHints: Bool

    private var filterFocusActive: Bool {
        selection.focusArea == .filters
    }

    var body: some View {
        HStack(spacing: 12) {
            if showButtonHints {
                badge("LB")
            }

            if searchVisible {
                searchField
            } else {
                filterRow
                searchButton
            }

            if showButtonHints {
                badge("RB")
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
    }

    private func badge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(SeleneTheme.ink.opacity(0.50))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(SeleneTheme.ink.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var filterRow: some View {
        HStack(spacing: 22) {
            ForEach(LibraryFilter.allCases) { filter in
                let index = LibraryFilter.allCases.firstIndex(of: filter) ?? 0
                let selected = selection.query.filter == filter
                let focused = filterFocusActive && selection.filterIndex == index

                Button {
                    selection.query.filter = filter
                    selection.filterIndex = index
                    selection.focusArea = .filters
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected
                                         ? SeleneTheme.scrim
                                         : SeleneTheme.ink.opacity(0.62))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(selected ? SeleneTheme.focus : Color.clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .seleneRowFocus(focused, radius: 16)
                .accessibilityLabel(filter.rawValue)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private var searchButton: some View {
        Button {
            selection.focusArea = .filters
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

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(SeleneTheme.ink.opacity(0.48))
            TextField("Search your library", text: $selection.query.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(SeleneTheme.ink)
                .focused(searchFocused)
                .onSubmit {
                    searchFocused.wrappedValue = false
                    selection.focusArea = .rail
                }
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
        .background(SeleneTheme.glass.opacity(0.88))
        .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: 1))
        .clipShape(Capsule())
    }
}
