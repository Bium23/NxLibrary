import SwiftUI
import NXLibraryCore

/// Selene's top bar (Main.xaml HubTopBarBackground + HomeNav.RenderFilterTabs):
/// 110 high, 64 side margins, LB · filter tabs · RB centered, clock on the right.
/// Shared by Spotlight and Collection.
struct SpotlightTopBar: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let filter: LibraryFilter
    var showClock: Bool = true
    var onSelect: (LibraryFilter) -> Void = { _ in }

    @State private var popScale: CGFloat = 1
    @State private var popOpacity: Double = 1

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                badge(.lb)
                ForEach(LibraryFilter.allCases) { tab($0) }
                badge(.rb)
            }
            HStack {
                Spacer()
                if showClock {
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .seleneFont(30)
                            .foregroundColor(SeleneTheme.ink)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, canvas.u(64))
        .frame(height: canvas.u(110))
        .onChange(of: filter) { _ in pop() }
    }

    private func tab(_ item: LibraryFilter) -> some View {
        let on = item == filter
        return Text(L10n.text(item.rawValue))
            .seleneFont(19, on ? .semibold : .regular)
            .foregroundColor(on ? SeleneTheme.onFocus : SeleneTheme.ink.opacity(0.7))
            .padding(EdgeInsets(top: canvas.u(5), leading: canvas.u(18),
                                bottom: canvas.u(7), trailing: canvas.u(20)))
            .background(
                RoundedRectangle(cornerRadius: canvas.u(18), style: .continuous)
                    .fill(on ? SeleneTheme.focus.opacity(0.95) : .clear)
            )
            .scaleEffect(on ? popScale : 1)
            .opacity(on ? popOpacity : 1)
            .padding(.horizontal, canvas.u(2))
            .contentShape(Rectangle())
            .onTapGesture { onSelect(item) }
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func badge(_ button: PromptButton) -> some View {
        SelenePromptBadge(button: button, height: 26)
            .padding(.horizontal, canvas.u(8))
            .accessibilityHidden(true)
    }

    /// The new tab pops 0.86 → 1 over 200 ms (cubic out) and fades 0.4 → 1 over
    /// 160 ms. Reduce motion drops the pop and keeps the fade.
    private func pop() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            popScale = reduceMotion ? 1 : 0.86
            popOpacity = 0.4
        }
        DispatchQueue.main.async {
            if !reduceMotion { withAnimation(SeleneTheme.cubicOut(0.2)) { popScale = 1 } }
            withAnimation(.linear(duration: 0.16)) { popOpacity = 1 }
        }
    }
}
