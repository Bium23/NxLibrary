import SwiftUI
import AppKit
import NXLibraryCore

/// The column and its rows: entries, hints, the info line, accessibility values and each row's trailing value.
extension GameOptionsView {
    func column(_ p: GameOptionsPresentation) -> some View {
        let entries = p.entries(level: level, origin: origin)
        let focused = focusedRow
        return VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("GAME OPTIONS"))
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(8))
            Text(current.name)
                .seleneFont(40)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.leading, canvas.u(6))
                // With the list's 6 top inset this keeps Selene's 20 under the name.
                .padding(.bottom, canvas.u(14))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(8)) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            entryView(entry, p, focused: focused)
                        }
                    }
                    // The clip would shave the first row's focus border.
                    .padding(.top, canvas.u(6))
                    .padding(.bottom, canvas.u(24))
                    // Rows are measured in the list's own space, which scrolling never changes.
                    .coordinateSpace(name: OptionsScrollBox.space)
                    .onPreferenceChange(OptionRowFrames.self) { scrollBox.frames = $0 }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: canvas.u(680))
                .onChange(of: focusedRow) { _, row in
                    // A focus that followed the wheel leaves the list where the user put it.
                    if scrollBox.holdScroll { scrollBox.holdScroll = false; return }
                    guard let row else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(row.rawValue, anchor: .center)
                    }
                }
            }
            .id(level)
        }
        .frame(width: canvas.u(1040), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(90))
        .padding(.bottom, canvas.u(110))
        // Clicks inside the column are not clicks on the scrim; only the dimmed area outside closes.
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func entryView(_ entry: GameOptionsEntry, _ p: GameOptionsPresentation,
                           focused: GameOptionsRow?) -> some View {
        switch entry {
        case .row(let row):
            rowView(row, p, focused: focused)
        case .heading(let text):
            Text(text)
                .seleneFont(17, .semibold)
                .foregroundColor(isSelene ? SeleneTheme.ink75 : SeleneTheme.glyph)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, canvas.u(26))
                .padding(.top, canvas.u(16))
        case .note(let title, let text):
            VStack(alignment: .leading, spacing: canvas.u(3)) {
                Text(title)
                    .seleneFont(21, .medium)
                    .foregroundColor(SeleneTheme.ink60)
                Text(text)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, canvas.u(26))
            .padding(.top, canvas.u(18))
            .padding(.trailing, canvas.u(24))
            .padding(.bottom, canvas.u(18))
            .background(RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous)
                .fill(SeleneTheme.glass))
        case .gap:
            // Stack spacing is 8u on each side, so 8u here makes the 24u gap before a danger zone.
            Color.clear.frame(height: canvas.u(8))
        }
    }

    /// Selene's headings are a soft ink, not its blue accent.
    private var isSelene: Bool { ThemeStore.shared.palette.id == SelenePaletteCatalog.defaultID }

    private func rowView(_ row: GameOptionsRow, _ p: GameOptionsPresentation,
                         focused: GameOptionsRow?) -> some View {
        SeleneOptionRow(icon: row.icon,
                        title: row.title,
                        about: p.about(row),
                        focused: focused == row,
                        destructive: row.isDestructive,
                        enabled: !p.isDimmed(row)) {
            HStack(spacing: canvas.u(12)) {
                if let info = p.info(row) {
                    SeleneInfoTip(info, isShowing: Binding(
                        get: { infoRow == row },
                        set: { show in
                            if show { setFocus(row) }
                            infoRow = show ? row : (infoRow == row ? nil : infoRow)
                        }))
                }
                trailing(row)
            }
        }
        .help(p.info(row) ?? "")
        .background(GeometryReader { geometry in
            Color.clear.preference(key: OptionRowFrames.self,
                                   value: [row: geometry.frame(in: .named(OptionsScrollBox.space))])
        })
        .contentShape(Rectangle())
        .onTapGesture { activate(row) }
        .id(row.rawValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityHint(p.about(row) ?? "")
        .accessibilityValue(accessibilityValue(row) ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(row) }
    }

    /// Y opens the focused row's explanation, when it has one.
    func rightHints(_ p: GameOptionsPresentation) -> [HintItem] {
        guard confirm == nil, let row = focusedRow, p.info(row) != nil else { return [HintItem(.a, L10n.text("Select"))] }
        return [HintItem(.y, infoRow == row ? L10n.text("Hide info") : L10n.text("Info")), HintItem(.a, L10n.text("Select"))]
    }

    /// Y: the focused row's explanation, open or closed.
    func toggleInfo() {
        guard confirm == nil, let row = focusedRow, presentation.info(row) != nil else { return }
        infoRow = infoRow == row ? nil : row
    }

    /// The state a VoiceOver user hears for a switch or a value chip.
    private func accessibilityValue(_ row: GameOptionsRow) -> String? {
        if row.isToggle { return toggleValue(row) ? "On" : "Off" }
        if row.isChoice { return choiceText(row) }
        if row == .cheats { return cheatsValue }
        if row == .mods { return presentation.modsValue }
        return nil
    }

    @ViewBuilder
    private func trailing(_ row: GameOptionsRow) -> some View {
        if row.isToggle {
            // The row takes the click; the switch only shows the state.
            SeleneSwitch(isOn: .constant(toggleValue(row))).allowsHitTesting(false)
        } else if row.isChoice {
            SeleneValueChip(text: choiceText(row))
        } else if row == .cheats || row == .mods {
            HStack(spacing: canvas.u(10)) {
                if row == .mods || cheatsValue != nil {
                    SeleneValueChip(text: row == .cheats ? presentation.cheatsValue : presentation.modsValue)
                }
                MaterialIconView(.chevron, size: 24)
                    .foregroundColor(SeleneTheme.ink60)
            }
        } else if row.opensSubmenu {
            MaterialIconView(.chevron, size: 24)
                .foregroundColor(SeleneTheme.ink60)
        } else {
            EmptyView()
        }
    }

    private func toggleValue(_ row: GameOptionsRow) -> Bool {
        if let (setting, value) = settingValue(row) {
            return value == (setting.kind == "toggle" ? setting.on : row.onValue)
        }
        switch row {
        case .favorite: return current.isFavorite
        case .hidden: return current.isHidden
        case .fullscreen: return config.fullscreen
        case .fps60: return config.enable60FPS
        case .metalFX: return config.enableMetalFXUpscale
        case .metalHUD: return config.enableMetalHUD
        case .rumble: return config.rumble
        default: return false
        }
    }

    private func choiceText(_ row: GameOptionsRow) -> String {
        if let (setting, value) = settingValue(row) { return L10n.text(GameSettingValues.label(setting, value)) }
        switch row {
        case .consoleMode:
            return GameOptionsValues.consoleModeLabel(docked: config.isDockedMode)
        case .language:
            return viewModel.availableLanguages.first { $0.code == config.language }?.label ?? config.language
        case .rumbleStrength:
            return "\(config.rumbleGain)"
        case .renderScale:
            return GameOptionsValues.renderScaleLabel(config.renderScale)
        default:
            return ""
        }
    }
}
