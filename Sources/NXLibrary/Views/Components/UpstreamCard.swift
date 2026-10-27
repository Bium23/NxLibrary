import SwiftUI
import NXLibraryCore

public struct UpstreamCard: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var isChecking: Bool {
        if case .checking = viewModel.upstreamState { return true }
        return false
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Upstream Changelog", systemImage: "arrow.triangle.branch")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)

                    Spacer()

                    Button(isChecking ? "Checking..." : "Check Upstream") {
                        viewModel.checkUpstreamChangelog()
                    }
                    .buttonStyle(NXSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(isChecking)
                }

                Text("Read-only. GitHub is contacted only when you press the button; the engine checkout and the pinned commit are never changed.")
                    .font(.system(size: 10))
                    .foregroundColor(NXTheme.textMuted)

                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.upstreamState {
        case .idle:
            Text("No upstream check yet. This compares the pinned engine commit with seedds/nxnative main.")
                .font(.system(size: 11))
                .foregroundColor(NXTheme.textSecondary)

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking GitHub for the latest commits...")
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
            }

        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(NXTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upstream check failed")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(NXTheme.warning)
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textSecondary)
                        .textSelection(.enabled)
                    Button("Retry") { viewModel.checkUpstreamChangelog() }
                        .buttonStyle(NXSecondaryButtonStyle())
                        .controlSize(.small)
                }
                Spacer()
            }
            .padding(8)
            .background(NXTheme.warning.opacity(0.08))
            .cornerRadius(8)

        case .loaded(let status):
            loaded(status)
        }
    }

    @ViewBuilder
    private func loaded(_ status: UpstreamStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(headline(status))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(headlineColor(status))
                Spacer()
                Text("Checked \(status.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NXTheme.textMuted)
            }

            HStack(spacing: 8) {
                commitColumn("Pinned", viewModel.pinnedEngineCommit)
                commitColumn("Local", viewModel.currentEngineCommit ?? "unknown")
                commitColumn("Upstream", status.upstreamCommit)
            }

            if !status.commits.isEmpty {
                VStack(spacing: 5) {
                    ForEach(status.commits.prefix(12)) { commit in
                        commitRow(commit)
                    }
                }

                if status.totalCommits > min(status.commits.count, 12) {
                    Text("Showing \(min(status.commits.count, 12)) of \(status.totalCommits) commits; open GitHub for the full list.")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textMuted)
                }
            }

            HStack(spacing: 8) {
                Button("Open Compare on GitHub") {
                    viewModel.openUpstreamCompare()
                }
                .buttonStyle(NXSecondaryButtonStyle())
                .controlSize(.small)
                .disabled(status.compareURL.absoluteString.isEmpty)

                Spacer()
            }

            Text("Updating is manual and untested. The toolchain gate keeps blocking new builds until the engine commit is re-pinned and the combination is re-tested.")
                .font(.system(size: 10))
                .foregroundColor(NXTheme.warning)
        }
    }

    private func headline(_ status: UpstreamStatus) -> String {
        if status.isUpToDate { return "Up to date with main" }
        if status.behindBy > 0 && status.aheadBy == 0 {
            return "Local is \(status.behindBy) commit\(status.behindBy == 1 ? "" : "s") behind main"
        }
        if status.behindBy > 0 && status.aheadBy > 0 {
            return "Local and main have diverged (\(status.aheadBy) new upstream, \(status.behindBy) local)"
        }
        return "\(status.aheadBy) new commit\(status.aheadBy == 1 ? "" : "s") on main"
    }

    private func headlineColor(_ status: UpstreamStatus) -> Color {
        if status.isUpToDate { return NXTheme.success }
        if status.behindBy > 0 { return NXTheme.warning }
        return NXTheme.primary
    }

    private func commitColumn(_ title: String, _ sha: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(NXTheme.textMuted)
            Text(short(sha))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(NXTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(NXTheme.glassSurfaceElevated.opacity(0.45))
        .cornerRadius(6)
    }

    private func commitRow(_ commit: UpstreamCommit) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(commit.shortSha)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(NXTheme.secondary)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 5) {
                    Text(dateText(commit.date))
                    Text("·")
                    Text(commit.author)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(NXTheme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(NXTheme.glassSurfaceElevated.opacity(0.35))
        .cornerRadius(6)
    }

    private func dateText(_ iso: String) -> String {
        iso.isEmpty ? "unknown date" : String(iso.prefix(10))
    }

    private func short(_ sha: String) -> String {
        sha.isEmpty || sha == "unknown" ? "unknown" : String(sha.prefix(7))
    }
}
