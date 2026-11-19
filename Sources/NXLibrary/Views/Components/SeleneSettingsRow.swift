import SwiftUI
import NXLibraryCore

/// An info button: a click shows `text` beside it. Pass `isShowing` for a screen that also opens it from the
/// keyboard or a controller.
struct SeleneInfoTip: View {
    @Environment(\.nxAppLocale) private var localization
    let text: String
    private let shown: Binding<Bool>?
    @State private var shownHere = false

    init(_ text: String, isShowing: Binding<Bool>? = nil) {
        self.text = text
        self.shown = isShowing
    }

    private var isShowing: Binding<Bool> { shown ?? $shownHere }

    var body: some View {
        Button {
            isShowing.wrappedValue.toggle()
        } label: {
            Image(systemName: "info.circle")
                .seleneFont(15, .semibold)
                .foregroundColor(isShowing.wrappedValue ? SeleneTheme.glyph : SeleneTheme.ink60.opacity(0.85))
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isShowing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(text, context: localization))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink.opacity(0.96))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 290, alignment: .leading)
            .background(SeleneTheme.glassSolid)
        }
        .help(L10n.text(text, context: localization))
        .accessibilityLabel(L10n.text("Information", context: localization))
        .accessibilityHint(L10n.text(text, context: localization))
    }
}

struct SeleneRow<Trailing: View>: View {
    @Environment(\.nxAppLocale) private var localization
    let rowID: String
    let title: String
    let subtitle: String?
    let info: String?
    let verbatimTitle: Bool
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.seleneFocusedRowID) private var focusedRowID

    init(_ title: String, id: String? = nil, subtitle: String? = nil, info: String? = nil, verbatimTitle: Bool = false,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.rowID = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.verbatimTitle = verbatimTitle
        self.trailing = trailing
    }

    private var isFocused: Bool { focusedRowID == rowID }

    var body: some View {
        SeleneOptionRow(icon: nil, title: verbatimTitle ? title : L10n.text(title, context: localization), about: subtitle.map { L10n.text($0, context: localization) }, focused: isFocused) {
            HStack(spacing: 10) {
                if let info {
                    SeleneInfoTip(info)
                }
                trailing()
            }
        }
        .id("selene-row-\(rowID)")
    }
}

struct SeleneToggleStyle: ToggleStyle {
    init() {}
    func makeBody(configuration: Configuration) -> some View {
        SeleneSwitch(isOn: configuration.$isOn)
    }
}

struct SeleneToggleRow: View {
    let title: String
    let subtitle: String?
    let info: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, info: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self._isOn = isOn
    }

    var body: some View {
        SeleneRow(title, subtitle: subtitle, info: info) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SeleneToggleStyle())
        }
    }
}

struct SeleneValueRow: View {
    let title: String
    let subtitle: String?
    let info: String?
    let value: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, subtitle: String? = nil, info: String? = nil, value: String,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.value = value
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        SeleneRow(title, subtitle: subtitle, info: info) {
            HStack(spacing: 10) {
                SeleneValueChip(text: value)
                if let actionTitle, let action {
                    Button(L10n.text(actionTitle), action: action)
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }
        }
    }
}

struct SeleneButtonRow: View {
    let rowID: String
    let title: String
    let subtitle: String?
    let info: String?
    let buttonTitle: String
    let verbatimTitle: Bool
    let action: () -> Void

    init(_ title: String, id: String? = nil, subtitle: String? = nil, info: String? = nil, verbatimTitle: Bool = false,
                buttonTitle: String, action: @escaping () -> Void) {
        self.rowID = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.verbatimTitle = verbatimTitle
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        SeleneRow(title, id: rowID, subtitle: subtitle, info: info, verbatimTitle: verbatimTitle) {
            Button(L10n.text(buttonTitle), action: action)
                .buttonStyle(.plain)
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.glyph)
        }
    }
}

struct SeleneSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .seleneFont(14, .semibold)
                        .foregroundColor(selection == option.0 ? SeleneTheme.scrim : SeleneTheme.ink.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selection == option.0 ? SeleneTheme.focus : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(SeleneTheme.ink.opacity(0.055))
        .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: 1))
        .clipShape(Capsule())
    }
}

struct SelenePanel<Content: View>: View {
    @Environment(\.nxAppLocale) private var localization
    let title: String?
    let info: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, info: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.info = info
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    Text(L10n.text(title, context: localization))
                        .seleneFont(12, .bold)
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundColor(SeleneTheme.ink60)
                    if let info {
                        SeleneInfoTip(info)
                    }
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.glassSolid)
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
    }
}

/// A value row that steps through its choices: Left/Right on a controller, the arrows with a pointer.
struct SeleneCycleRow: View {
    let title: String
    let subtitle: String?
    let info: String?
    let value: String
    let cycle: (Int) -> Void

    init(_ title: String, subtitle: String? = nil, info: String? = nil, value: String,
                cycle: @escaping (Int) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.value = value
        self.cycle = cycle
    }

    var body: some View {
        SeleneRow(title, subtitle: subtitle, info: info) {
            HStack(spacing: 6) {
                arrow(.chevronLeft, -1)
                SeleneValueChip(text: L10n.text(value))
                arrow(.chevron, 1)
            }
        }
    }

    private func arrow(_ icon: MaterialIcon, _ delta: Int) -> some View {
        Button { cycle(delta) } label: {
            MaterialIconView(icon, size: 20)
                .foregroundColor(SeleneTheme.ink60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? L10n.format("Previous %@", [String(describing: title)]) : L10n.format("Next %@", [String(describing: title)]))
    }
}

extension CaseIterable where Self: Equatable {
    /// The case `delta` steps away, wrapping at both ends.
    func stepped(_ delta: Int) -> Self {
        let all = Array(Self.allCases)
        let index = all.firstIndex(of: self) ?? 0
        let count = all.count
        return all[((index + delta) % count + count) % count]
    }
}

extension Array where Element: Equatable {
    /// The element `delta` steps from `current`, wrapping; the first element when `current` is absent.
    func stepped(from current: Element, _ delta: Int) -> Element? {
        guard !isEmpty else { return nil }
        guard let index = firstIndex(of: current) else { return first }
        return self[((index + delta) % count + count) % count]
    }
}
