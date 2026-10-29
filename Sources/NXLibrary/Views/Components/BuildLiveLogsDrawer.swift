import SwiftUI

public struct BuildLiveLogsDrawer: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live output", systemImage: "terminal")
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.ink90)
                Spacer()
                Text("\(viewModel.logs.count) lines")
                    .seleneFont(13, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if viewModel.logs.isEmpty {
                            Text("Waiting for build output…")
                                .seleneFont(13, .regular, design: .monospaced)
                                .foregroundColor(SeleneTheme.ink60)
                        }
                        let recentLogs = viewModel.logs.suffix(80)
                        ForEach(Array(recentLogs.enumerated()), id: \.offset) { index, log in
                            HStack(alignment: .top, spacing: 6) {
                                Text(log.message)
                                    .seleneFont(13, .regular, design: .monospaced)
                                    .foregroundColor(logColor(log.level))
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .id(index)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .background(SeleneTheme.scrim)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: viewModel.logs.count) { _ in
                    let recentCount = viewModel.logs.suffix(80).count
                    if recentCount > 0 {
                        proxy.scrollTo(recentCount - 1, anchor: .bottom)
                    }
                }
            }
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

    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return SeleneTheme.ink90
        case .step: return SeleneTheme.glyph
        case .success: return SeleneTheme.success
        case .warning: return SeleneTheme.untested
        case .error: return SeleneTheme.danger
        }
    }
}
