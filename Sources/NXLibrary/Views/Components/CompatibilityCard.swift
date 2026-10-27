import SwiftUI
import NXLibraryCore

public struct CompatibilityCard: View {
    @ObservedObject public var viewModel: AppViewModel
    @State private var showOverrideConfirmation = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                engineLine

                VStack(spacing: 7) {
                    if let report = viewModel.compatibilityReport {
                        ForEach(report.checks, id: \.id) { check in
                            checkRow(title: check.title, status: check.status,
                                     detail: detail(for: check))
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Running the compatibility check...")
                                .font(.system(size: 11))
                                .foregroundColor(NXTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }

                    environmentRows
                }

                if let issues = viewModel.environmentStatus?.issues, !issues.isEmpty {
                    Text(issues.joined(separator: " · "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(NXTheme.warning)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NXTheme.warning.opacity(0.09))
                        .cornerRadius(8)
                }

                if viewModel.compatibilityReport?.checks.contains(where: {
                    $0.id == "metal" && $0.status == .block
                }) == true {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(NXTheme.warning)
                        Text("Only the exact Metal compiler pinned by nxnative is accepted. Play remains available; new builds and rebuilds are blocked until the matching Xcode/Metal toolchain is installed, or until the override below is enabled.")
                            .font(.system(size: 10))
                            .foregroundColor(NXTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(8)
                    .background(NXTheme.warning.opacity(0.07))
                    .cornerRadius(8)
                }

                if viewModel.compatibilityReport?.ok == false {
                    Divider().opacity(0.2)
                    overrideControls
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Compatibility Gate", systemImage: "checkmark.shield.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(NXTheme.textPrimary)

            Spacer()

            Text(statusText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.14))
                .foregroundColor(statusColor)
                .clipShape(Capsule())

            Button("Re-check") {
                viewModel.refreshCompatibility()
            }
            .buttonStyle(NXSecondaryButtonStyle())
            .controlSize(.small)
        }
    }

    private var engineLine: some View {
        HStack(spacing: 8) {
            Text("Pinned \(short(viewModel.pinnedEngineCommit))")
            Text("·")
            Text("Current \(short(viewModel.currentEngineCommit))")
            Spacer()
            if let metal = viewModel.installedMetalVersion {
                Text("Metal \(metal)")
                    .foregroundColor(NXTheme.textMuted)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(NXTheme.textSecondary)
    }

    @ViewBuilder
    private var environmentRows: some View {
        if let environment = viewModel.environmentStatus {
            checkRow(
                title: "Xcode",
                status: environment.xcodeVersion == nil ? .block : .pass,
                detail: environment.xcodeVersion ?? "not found"
            )
            if let spv = environment.tools.first(where: { $0.id == "spirv-cross" }) {
                checkRow(
                    title: "spv-cross",
                    status: spv.ok ? .pass : .block,
                    detail: spv.detail
                )
            }
        }
    }

    private var overrideControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.allowUntestedToolchain },
                set: { newValue in
                    if newValue {
                        showOverrideConfirmation = true
                    } else {
                        viewModel.allowUntestedToolchain = false
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build anyway with an untested toolchain")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(NXTheme.textPrimary)
                    Text("The build will be recorded as untested. Corrupted graphics are a known risk.")
                        .font(.system(size: 10))
                        .foregroundColor(NXTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if viewModel.allowUntestedToolchain {
                Text("Override enabled. New builds are allowed and flagged as untested.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(NXTheme.warning)
            }
        }
        .alert("Enable the untested-toolchain override?", isPresented: $showOverrideConfirmation) {
            Button("Enable Override", role: .destructive) {
                viewModel.allowUntestedToolchain = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The installed engine, Metal compiler or CLI do not match the certified combination. Builds may produce corrupted pictures or fail. Each build made this way is marked as untested.")
        }
    }

    private var statusText: String {
        guard let report = viewModel.compatibilityReport else { return "Checking" }
        if report.ok { return "Certified" }
        if viewModel.allowUntestedToolchain { return "Override enabled" }
        return "Blocked"
    }

    private var statusColor: Color {
        guard let report = viewModel.compatibilityReport else { return NXTheme.textMuted }
        if report.ok { return NXTheme.success }
        if viewModel.allowUntestedToolchain { return NXTheme.warning }
        return NXTheme.error
    }

    private func detail(for check: CompatibilityCheck) -> String {
        if check.id == "metal" {
            let installed = viewModel.installedMetalVersion ?? "unknown"
            let required = viewModel.requiredMetalVersion ?? "unknown"
            return "installed \(installed) · required \(required)"
        }
        return check.detail
    }

    private func checkRow(title: String, status: CheckStatus, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(for: status))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color(for: status))
                .frame(width: 15)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NXTheme.textPrimary)
                .frame(width: 96, alignment: .leading)

            Text(detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(NXTheme.textSecondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Text(status.rawValue.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(color(for: status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(NXTheme.glassSurfaceElevated.opacity(0.5))
        .cornerRadius(6)
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
        case .pass: return NXTheme.success
        case .warn: return NXTheme.warning
        case .block: return NXTheme.error
        }
    }

    private func short(_ commit: String?) -> String {
        guard let commit, !commit.isEmpty else { return "unknown" }
        return String(commit.prefix(7))
    }
}
