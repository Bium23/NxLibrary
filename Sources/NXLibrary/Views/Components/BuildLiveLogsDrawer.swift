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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SeleneTheme.inkSecondary)
                Spacer()
                Text("\(viewModel.logs.count) lines")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(SeleneTheme.inkMuted)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if viewModel.logs.isEmpty {
                            Text("Waiting for build output…")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(SeleneTheme.inkMuted)
                        }
                        let recentLogs = viewModel.logs.suffix(80)
                        ForEach(Array(recentLogs.enumerated()), id: \.offset) { index, log in
                            HStack(alignment: .top, spacing: 6) {
                                Text(log.message)
                                    .font(.system(size: 10, design: .monospaced))
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
                .background(SeleneTheme.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SeleneTheme.border, lineWidth: 1)
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
        .background(SeleneTheme.canvasRaised)
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(SeleneTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
    }

    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return SeleneTheme.inkSecondary
        case .step: return SeleneTheme.accent
        case .success: return SeleneTheme.success
        case .warning: return SeleneTheme.warning
        case .error: return SeleneTheme.danger
        }
    }
}
