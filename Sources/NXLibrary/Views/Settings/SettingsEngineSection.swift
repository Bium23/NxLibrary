import SwiftUI
import NXLibraryCore

struct SettingsEngineSection: View {
    @ObservedObject var viewModel: AppViewModel
    let onActions: ([SettingsRowAction]) -> Void

    @Environment(\.seleneFocusedRowTitle) private var focusedRowTitle
    @State private var showOverrideConfirmation = false

    var body: some View {
        VStack(spacing: 9) {
            SeleneRow("Engine repository",
                      subtitle: "The upstream nxnative checkout used for builds. Updates stay manual.") {
                HStack(spacing: 10) {
                    Text(viewModel.nxnativePath.isEmpty ? "Not selected" : viewModel.nxnativePath)
                        .seleneFont(15, .medium)
                        .foregroundColor(SeleneTheme.ink.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .trailing)
                    Button("Change") { viewModel.selectNxnativeFolder() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                    Button("Reveal") {
                        viewModel.revealInFinder(url: URL(fileURLWithPath: viewModel.nxnativePath))
                    }
                    .buttonStyle(.plain)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                    .disabled(!viewModel.isNxnativeValid)
                }
            }

            SeleneValueRow("Pinned commit", value: seleneShort(viewModel.pinnedEngineCommit))
            SeleneValueRow("Current commit", value: seleneShort(viewModel.currentEngineCommit))

            SelenePanel("Compatibility",
                        info: "Audits the local engine commit, working tree cleanliness, installed Metal compiler, and required CLI flags against the certified toolchain lock.") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .seleneFont(15, .semibold)
                        .foregroundColor(statusColor)
                    Spacer()
                    Button("Re-check") { viewModel.detectEnvironment() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }

                if let message = viewModel.toolchainGateSummary?.message {
                    Text(message)
                        .seleneFont(14)
                        .foregroundColor(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let report = viewModel.compatibilityReport {
                    ForEach(report.checks, id: \.id) { check in
                        checkRow(title: check.title, status: check.status, detail: detail(for: check),
                                 metal: check.id == "metal" ? report.metal : nil)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running the compatibility check...")
                            .seleneFont(15)
                            .foregroundColor(SeleneTheme.ink60)
                    }
                }

                if let environment = viewModel.environmentStatus {
                    Divider().overlay(SeleneTheme.ink15)
                    buildRow("Xcode", ok: environment.xcodeVersion != nil,
                             detail: environment.xcodeVersion ?? "not found")
                    buildRow("Metal compiler", ok: environment.metalVersion != nil,
                             detail: environment.metalVersion ?? "not found")
                    buildRow("Python and build tools", ok: environment.pythonURL != nil,
                             detail: runtimeDetail(environment))
                    buildRow(".NET 10 runtime", ok: !environment.issues.contains {
                        $0.lowercased().contains(".net")
                    }, detail: "checked by the build command")
                    ForEach(environment.tools) { tool in
                        buildRow(tool.name, ok: tool.ok, detail: tool.detail)
                    }

                    if !environment.issues.isEmpty {
                        Text(environment.issues.joined(separator: " · "))
                            .seleneFont(13, .regular, design: .monospaced)
                            .foregroundColor(SeleneTheme.untested)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .seleneRowFocus(focusedRowTitle == "Compatibility", radius: SeleneTheme.cardRadius)

            SeleneRow("Untested toolchain override",
                      subtitle: overrideSubtitle,
                      info: "Permits building games when your installed Metal compiler or Xcode differs from the certified version (Xcode 27.1, Metal 32023.921). Passes --allow-other-metal to nxnative. Builds are recorded as unverified.") {
                Toggle("", isOn: overrideBinding)
                    .labelsHidden()
                    .toggleStyle(SeleneToggleStyle())
                    .disabled(viewModel.compatibilityReport?.ok != false)
                    .accessibilityValue(viewModel.allowUntestedToolchain ? "On" : "Off")
            }

            SeleneButtonRow("Upstream",
                            subtitle: upstreamSubtitle,
                            buttonTitle: upstreamButtonTitle) {
                viewModel.checkUpstreamChangelog()
            }

            if case .loaded(let status) = viewModel.upstreamState {
                upstreamCommitsPanel(status)

                SeleneButtonRow("Compare",
                                subtitle: status.isUpToDate
                                    ? "The pinned commit matches upstream main."
                                    : "Open the commit comparison on GitHub.",
                                buttonTitle: "Open GitHub") {
                    viewModel.openUpstreamCompare()
                }
            }

            SelenePanel("prod.keys",
                        info: "Nintendo Switch cryptographic keys required to decrypt game packages (NSP/XCI). NX Library stores a private copy with mode 0600 permissions; key values are never displayed or logged.") {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isProdKeysValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .seleneFont(15, .bold)
                        .foregroundColor(viewModel.isProdKeysValid ? SeleneTheme.success : SeleneTheme.danger)
                    Text(viewModel.isProdKeysValid ? "Keys imported" : "No prod.keys imported")
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Spacer()
                    Text(viewModel.isProdKeysValid && !viewModel.prodKeysPath.isEmpty
                         ? viewModel.prodKeysPath : "Choose your file once")
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let summary = viewModel.keySummary {
                    Text("header_key present · \(summary.applicationKeyGenerations.count) application key generations")
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.success)
                }

                HStack(spacing: 14) {
                    Button(viewModel.isProdKeysValid ? "Replace Key..." : "Import Key...") {
                        viewModel.selectProdKeysFile()
                    }
                    .buttonStyle(.plain)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.glyph)
                    Button("Detect Ryujinx...") { viewModel.selectRyujinxFolder() }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                    Spacer()
                }

                Text("The original file is untouched. The stored copy is mode 0600 and key values are never shown or logged.")
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .seleneRowFocus(focusedRowTitle == "prod.keys", radius: SeleneTheme.cardRadius)
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.allowUntestedToolchain) { _ in publishActions() }
        .alert("Enable the untested-toolchain override?", isPresented: $showOverrideConfirmation) {
            Button("Enable Override", role: .destructive) {
                viewModel.allowUntestedToolchain = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The installed engine, Metal compiler or CLI do not match the certified combination. Builds may produce corrupted pictures or fail. Each build made this way is marked as untested.")
        }
    }

    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { viewModel.allowUntestedToolchain },
            set: { newValue in
                if newValue {
                    showOverrideConfirmation = true
                } else {
                    viewModel.allowUntestedToolchain = false
                }
            }
        )
    }

    private var overrideSubtitle: String {
        guard let report = viewModel.compatibilityReport else {
            return "Available when the compatibility gate blocks a build."
        }
        if report.ok {
            return "Not needed: the current toolchain is certified."
        }
        if viewModel.toolchainGateSummary?.tone == .info {
            return "Recommended for your newer Metal compiler: builds are recorded as untested."
        }
        return "Build anyway, recorded as untested. Corrupted graphics are a known risk."
    }

    private var statusText: String {
        viewModel.toolchainGateSummary?.label ?? "Checking"
    }

    private var statusColor: Color {
        guard let summary = viewModel.toolchainGateSummary else { return SeleneTheme.ink60 }
        switch summary.tone {
        case .certified: return SeleneTheme.success
        case .info: return SeleneTheme.glyph
        case .warning, .override: return SeleneTheme.untested
        case .blocked: return SeleneTheme.danger
        }
    }

    private var upstreamSubtitle: String {
        switch viewModel.upstreamState {
        case .idle:
            return "Compare the pinned commit with seedds/nxnative main."
        case .checking:
            return "Asking GitHub for the latest commits..."
        case .loaded(let status):
            if status.isUpToDate {
                return "Pinned commit is up to date."
            }
            let count = status.newCommitsCount
            return "\(count) new commit\(count == 1 ? "" : "s") available upstream."
        case .failed(let message):
            return message
        }
    }

    private var upstreamButtonTitle: String {
        if case .checking = viewModel.upstreamState { return "Checking..." }
        return "Check"
    }

    @ViewBuilder
    private func upstreamCommitsPanel(_ status: UpstreamStatus) -> some View {
        if !status.commits.isEmpty {
            SelenePanel("Upstream Commits (\(status.newCommitsCount) newer)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(status.commits.prefix(10)) { commit in
                        HStack(alignment: .top, spacing: 10) {
                            Text(commit.shortSha)
                                .seleneFont(14, .bold, design: .monospaced)
                                .foregroundColor(SeleneTheme.glyph)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SeleneTheme.glyph.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.subject)
                                    .seleneFont(15, .medium)
                                    .foregroundColor(SeleneTheme.ink)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 6) {
                                    Text(commit.author)
                                        .seleneFont(13)
                                        .foregroundColor(SeleneTheme.ink60)
                                    if !commit.date.isEmpty {
                                        Text("·")
                                            .seleneFont(13)
                                            .foregroundColor(SeleneTheme.ink60.opacity(0.5))
                                        Text(formattedCommitDate(commit.date))
                                            .seleneFont(13)
                                            .foregroundColor(SeleneTheme.ink60)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        if commit.id != status.commits.prefix(10).last?.id {
                            Divider()
                                .background(SeleneTheme.ink15)
                        }
                    }

                    if status.commits.count > 10 {
                        HStack {
                            Text("+ \(status.commits.count - 10) more commits upstream")
                                .seleneFont(14, .medium)
                                .foregroundColor(SeleneTheme.ink60)
                            Spacer()
                            Button("View all on GitHub") {
                                viewModel.openUpstreamCompare()
                            }
                            .buttonStyle(.plain)
                            .seleneFont(14, .semibold)
                            .foregroundColor(SeleneTheme.glyph)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .seleneRowFocus(focusedRowTitle == "Upstream Commits", radius: SeleneTheme.cardRadius)
        }
    }

    private func formattedCommitDate(_ raw: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: raw) else { return raw }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private func detail(for check: CompatibilityCheck) -> String {
        if check.id == "metal" {
            let installed = viewModel.installedMetalVersion ?? "unknown"
            let required = viewModel.requiredMetalVersion ?? "unknown"
            return "installed \(installed) · required \(required)"
        }
        return check.detail
    }

    /// `metal` (the Metal row only): a newer compiler reads as information, an older one as a warning, not as BLOCK.
    private func checkRow(title: String, status: CheckStatus, detail: String, metal: MetalStanding? = nil) -> some View {
        let look = rowLook(status: status, metal: metal)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: look.icon)
                .seleneFont(15, .bold)
                .foregroundColor(look.color)
                .frame(width: 14)
            Text(title)
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .frame(width: 96, alignment: .leading)
            Text(detail)
                .seleneFont(13, .regular, design: .monospaced)
                .foregroundColor(SeleneTheme.ink60)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Text(look.badge)
                .seleneFont(11, .bold, design: .monospaced)
                .foregroundColor(look.color)
        }
    }

    private func rowLook(status: CheckStatus, metal: MetalStanding?) -> (icon: String, color: Color, badge: String) {
        switch metal {
        case .newer: return ("info.circle.fill", SeleneTheme.glyph, "NEWER")
        case .older: return ("exclamationmark.triangle.fill", SeleneTheme.untested, "OLDER")
        default: return (icon(for: status), color(for: status), status.rawValue.uppercased())
        }
    }

    private func runtimeDetail(_ environment: EnvironmentStatus) -> String {
        guard let python = environment.pythonURL else { return "missing" }
        if viewModel.engineToolchain.isBundled {
            return BundledRuntime.locate()?.versionSummary() ?? "Included in NX Library"
        }
        return "Developer build: \(python.path)"
    }

    private func buildRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .seleneFont(13, .bold)
                .foregroundColor(ok ? SeleneTheme.success : SeleneTheme.danger)
                .frame(width: 13)
            Text(title)
                .seleneFont(14, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.9))
                .frame(width: 116, alignment: .leading)
            Text(detail)
                .seleneFont(13, .regular, design: .monospaced)
                .foregroundColor(SeleneTheme.ink60)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func icon(for status: CheckStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .block: return "xmark.octagon.fill"
        }
    }

    private func color(for status: CheckStatus) -> Color {
        switch status {
        case .pass: return SeleneTheme.success
        case .warn: return SeleneTheme.untested
        case .block: return SeleneTheme.danger
        }
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = [
            .init(id: "repo", title: "Engine repository") {
                viewModel.selectNxnativeFolder()
            },
            .init(id: "recheck", title: "Compatibility") {
                viewModel.detectEnvironment()
            },
            .init(id: "override", title: "Untested toolchain override",
                  isEnabled: viewModel.compatibilityReport?.ok == false) {
                if viewModel.allowUntestedToolchain {
                    viewModel.allowUntestedToolchain = false
                } else {
                    showOverrideConfirmation = true
                }
            },
            .init(id: "upstream", title: "Upstream") {
                viewModel.checkUpstreamChangelog()
            }
        ]
        if case .loaded = viewModel.upstreamState {
            actions.append(.init(id: "compare", title: "Compare") {
                viewModel.openUpstreamCompare()
            })
        }
        actions.append(.init(id: "keys", title: "prod.keys") {
            viewModel.selectProdKeysFile()
        })
        onActions(actions)
    }
}
