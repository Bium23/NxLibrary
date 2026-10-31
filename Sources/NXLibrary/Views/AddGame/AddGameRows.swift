import SwiftUI
import NXLibraryCore

/// One line of Add game's list, top to bottom. Rows take the focus; headings and
/// notes only read. Up/Down move between rows, Left/Right change a switch or a
/// choice, A runs the row (a field starts editing).
struct AddGameRow: Identifiable {
    enum Kind {
        case action(() -> Void)
        case toggle(Binding<Bool>)
        /// Steps through `values`, the current one at `index`.
        case choice(values: [String], index: Int, select: (Int) -> Void)
        case field(Binding<String>, placeholder: String)
        case heading
        case note
        case warning(action: (() -> Void)?)
    }

    let id: String
    var kind: Kind
    var icon: MaterialIcon? = nil
    var title: String
    var about: String? = nil
    /// Icon colour on Selene (Game options' per-kind hues).
    var tint: String? = nil
    var enabled = true
    var destructive = false
    /// Smaller type and padding: sources, switches, fields.
    var compact = false
    /// A check at the end (the selected game of a folder).
    var checked = false

    var focusable: Bool {
        switch kind {
        case .heading, .note: return false
        case .warning(let action): return action != nil
        default: return true
        }
    }

    // Game options' hues: green go, sky place, orange build, lilac change, slate tools, amber keys, teal links.
    static let green = "#7BD88F", sky = "#7CC4FA", orange = "#F5A35C", lilac = "#C3A4F5"
    static let slate = "#A9B4C6", amber = "#F5C451", teal = "#6FD3C2", blue = "#8FB8F5"
}

/// Draws one `AddGameRow` in Game options' glass row look, a size smaller.
struct AddGameRowView: View {
    @Environment(\.seleneCanvas) private var canvas

    let row: AddGameRow
    let focused: Bool
    let isSelene: Bool
    var editing: FocusState<String?>.Binding

    var body: some View {
        switch row.kind {
        case .heading:
            Text(row.title.uppercased())
                .seleneFont(13, .semibold)
                .tracking(1.2)
                .foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, canvas.u(10))
                .padding(.top, canvas.u(18))
                .padding(.bottom, canvas.u(2))
        case .note:
            Text(row.title)
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink60)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, canvas.u(10))
                .padding(.top, canvas.u(10))
        case .warning:
            warning
        default:
            glassRow
        }
    }

    private var glassRow: some View {
        let radius = canvas.u(row.compact ? 13 : 16)
        let ink = row.destructive ? PortingPillCopy.softRed : (row.enabled ? SeleneTheme.ink : SeleneTheme.ink60)
        return HStack(spacing: canvas.u(row.compact ? 14 : 18)) {
            if let icon = row.icon {
                MaterialIconView(icon, size: row.compact ? 19 : 22)
                    .foregroundColor(iconColor)
                    .frame(width: canvas.u(row.compact ? 22 : 26))
            }
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                Text(row.title)
                    .seleneFont(row.compact ? 16 : 19, .medium)
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let about = row.about, !about.isEmpty {
                    Text(about)
                        .seleneFont(row.compact ? 13 : 14)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: canvas.u(14))
            trailing
        }
        .padding(.leading, canvas.u(row.compact ? 20 : 24))
        .padding(.trailing, canvas.u(row.compact ? 18 : 22))
        .padding(.vertical, canvas.u(row.compact ? 10 : 15))
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(row.compact ? SeleneTheme.glassLight : SeleneTheme.glass))
        .seleneRowFocus(focused, radius: radius)
        .opacity(row.enabled ? 1 : 0.7)
    }

    private var iconColor: Color {
        if row.destructive { return PortingPillCopy.softRed }
        guard row.enabled else { return SeleneTheme.ink60 }
        if isSelene, let hex = row.tint.flatMap({ UInt32($0.dropFirst(), radix: 16) }) { return Color(hex: hex) }
        return SeleneTheme.glyph
    }

    @ViewBuilder private var trailing: some View {
        switch row.kind {
        case .toggle(let isOn):
            SeleneSwitch(isOn: isOn)
                .scaleEffect(0.85)
                .allowsHitTesting(false)
        case .choice(let values, let index, _):
            SeleneValueChip(text: values.indices.contains(index) ? values[index] : "—")
        case .field(let text, let placeholder):
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .seleneFont(14, .regular, design: .monospaced)
                .foregroundColor(SeleneTheme.ink)
                .multilineTextAlignment(.trailing)
                .focused(editing, equals: row.id)
                .frame(width: canvas.u(320))
        case .action where row.checked:
            MaterialIconView(.check, size: 20)
                .foregroundColor(SeleneTheme.ink)
        default:
            EmptyView()
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: canvas.u(12)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .seleneFont(14)
                .foregroundColor(SeleneTheme.untested.opacity(0.9))
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                Text(row.title)
                    .seleneFont(15, .medium)
                    .foregroundColor(SeleneTheme.ink)
                if let about = row.about {
                    Text(about)
                        .seleneFont(13)
                        .foregroundColor(SeleneTheme.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, canvas.u(20))
        .padding(.vertical, canvas.u(11))
        .background(RoundedRectangle(cornerRadius: canvas.u(13), style: .continuous)
            .fill(SeleneTheme.untested.opacity(0.08)))
        .seleneRowFocus(focused, radius: canvas.u(13))
    }
}
