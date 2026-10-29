import SwiftUI
import NXLibraryCore

public struct SetupView: View {
    @ObservedObject public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            VStack(spacing: 0) {
                header(metrics)
                ScrollViewReader { proxy in
                    stepStrip(metrics) { id in
                        scroll(to: id, proxy: proxy)
                    }
                    ScrollView {
                        HStack(alignment: .top, spacing: 20) {
                            leftColumn
                                .frame(maxWidth: .infinity)
                            rightColumn
                                .frame(width: 380)
                        }
                        .padding(.horizontal, metrics.margin)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
                footer(metrics)
            }
        }
        .frame(minWidth: 980, idealWidth: 1120, minHeight: 760, idealHeight: 820)
        .background(SeleneTheme.scrim)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.detectEnvironment()
            if viewModel.importedApps.isEmpty {
                viewModel.importExistingBuilds()
            }
        }
    }

    // MARK: - Header and steps

    private func header(_ metrics: SeleneLayoutMetrics) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup")
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1.2)
                    .foregroundColor(SeleneTheme.ink)
                Text("Get the engine, keys and folders ready. Nothing is installed or changed automatically.")
                    .font(.system(size: 13))
                    .foregroundColor(SeleneTheme.ink60)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                statusPill(ok: viewModel.canCompleteSetup,
                           on: "Ready to finish",
                           off: "\(completedStepCount) of 5 checks")
                Button("Not Now") {
                    viewModel.showSetupSheet = false
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(SeleneTheme.ink60)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, 34)
        .padding(.bottom, 20)
    }

    private func stepStrip(_ metrics: SeleneLayoutMetrics,
                           onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(stepDefinitions) { step in
                Button {
                    onSelect(step.id)
                } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(step.isComplete ? SeleneTheme.success.opacity(0.2)
                                      : (step.isCurrent ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.08)))
                                .frame(width: 18, height: 18)
                            if step.isComplete {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(SeleneTheme.success)
                            } else {
                                Text("\(step.number)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(step.isCurrent ? SeleneTheme.scrim : SeleneTheme.ink.opacity(0.55))
                            }
                        }
                        Text(step.title)
                            .font(.system(size: 10.5, weight: step.isCurrent ? .semibold : .medium))
                            .foregroundColor(step.isCurrent ? SeleneTheme.scrim
                                             : (step.isComplete ? SeleneTheme.ink.opacity(0.82) : SeleneTheme.ink.opacity(0.48)))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(step.isCurrent ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.035))
                    .overlay(Capsule().strokeBorder(
                        step.isComplete ? SeleneTheme.success.opacity(0.28) : SeleneTheme.ink15,
                        lineWidth: 1
                    ))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(step.title), \(step.isComplete ? "complete" : "not complete")")
            }
            Spacer()
        }
        .padding(.horizontal, metrics.margin)
        .padding(.bottom, 8)
    }

    private var stepDefinitions: [SetupStep] {
        let environment = viewModel.environmentStatus?.canBuild == true
        let keys = viewModel.isProdKeysValid
        let folders = viewModel.libraryFolder != nil
        let compatibility = viewModel.compatibilityReport?.ok == true
        let imported = !viewModel.importedApps.isEmpty
        let values: [(String, String, Bool)] = [
            ("environment", "Environment", environment),
            ("keys", "Keys", keys),
            ("folders", "Folders", folders),
            ("compatibility", "Compatibility", compatibility),
            ("import", "Import", imported)
        ]
        let currentIndex = values.firstIndex(where: { !$0.2 }) ?? values.count - 1
        return values.enumerated().map { index, value in
            SetupStep(id: value.0, number: index + 1, title: value.1,
                      isComplete: value.2, isCurrent: index == currentIndex)
        }
    }

    private var completedStepCount: Int {
        var count = 0
        if viewModel.environmentStatus?.canBuild == true { count += 1 }
        if viewModel.isProdKeysValid { count += 1 }
        if viewModel.libraryFolder != nil { count += 1 }
        if viewModel.compatibilityReport?.ok == true { count += 1 }
        if !viewModel.importedApps.isEmpty { count += 1 }
        return count
    }

    private func scroll(to id: String, proxy: ScrollViewProxy) {
        let animation = reduceMotion ? nil : SeleneTheme.standard
        withAnimation(animation) {
            proxy.scrollTo(id, anchor: .top)
        }
        SoundEffectService.shared.play(.focus)
    }

    // MARK: - Columns

    private var leftColumn: some View {
        VStack(spacing: 16) {
            environmentPanel.id("environment")
            keysPanel.id("keys")
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 16) {
            foldersPanel.id("folders")
            compatibilityPanel.id("compatibility")
            importPanel.id("import")
        }
    }

    // MARK: - Environment

    private var environmentPanel: some View {
        SelenePanel("Environment") {
            sectionHeader(icon: "wrench.and.screwdriver.fill",
                          title: "Build toolchain",
                          detail: viewModel.environmentStatus?.canBuild == true
                            ? "Xcode, Metal and the Python venv are ready."
                            : "NX Library checks the tools nxnative needs before a build.",
                          ok: viewModel.environmentStatus?.canBuild == true)

            if let environment = viewModel.environmentStatus {
                HStack(spacing: 10) {
                    summaryCell("Xcode", environment.xcodeVersion ?? "missing")
                    summaryCell("Metal", environment.metalVersion ?? "missing")
                    summaryCell("Python", environment.pythonURL?.lastPathComponent ?? "missing")
                }
                if !environment.issues.isEmpty {
                    warningLine(environment.issues.joined(separator: " · "))
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking the nxnative toolchain…")
                        .font(.system(size: 11))
                        .foregroundColor(SeleneTheme.ink90)
                }
            }

            HStack(spacing: 10) {
                Text("Used in place at \(viewModel.nxnativePath)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Re-check") { viewModel.detectEnvironment() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
            }
        }
    }

    // MARK: - Keys

    private var keysPanel: some View {
        SelenePanel("Keys") {
            sectionHeader(icon: "key.fill",
                          title: "prod.keys",
                          detail: "Copied once into Application Support with 0600 permissions. Values are never shown or logged.",
                          ok: viewModel.isProdKeysValid)

            SeleneRow("Key file",
                      subtitle: viewModel.isProdKeysValid
                        ? "The stored copy is used by nxnative."
                        : "Choose your prod.keys once.") {
                HStack(spacing: 10) {
                    Text(viewModel.isProdKeysValid && !viewModel.prodKeysPath.isEmpty
                         ? viewModel.prodKeysPath
                         : "Not imported")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220, alignment: .trailing)
                    Button(viewModel.isProdKeysValid ? "Replace…" : "Import…") {
                        viewModel.selectProdKeysFile()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
                }
            }

            HStack(spacing: 10) {
                Button("Detect from Ryujinx…") { viewModel.selectRyujinxFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
                Spacer()
                if let summary = viewModel.keySummary {
                    Text("\(summary.applicationKeyGenerations.count) application key generations")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(SeleneTheme.ink60)
                }
            }
        }
    }

    // MARK: - Folders

    private var foldersPanel: some View {
        SelenePanel("Folders") {
            sectionHeader(icon: "folder.fill",
                          title: "Locations",
                          detail: "Built apps go to the app library. Sources are referenced where they are.",
                          ok: viewModel.libraryFolder != nil)

            SeleneRow("App library",
                      subtitle: viewModel.libraryFolder?.path ?? "~/Applications") {
                Button("Change…") { viewModel.selectLibraryFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
            }

            SeleneRow("Game sources",
                      subtitle: viewModel.selectedGameFolder?.path
                        ?? "Optional. Add Game remembers the last folder you use.") {
                HStack(spacing: 10) {
                    Button(viewModel.selectedGameFolder == nil ? "Choose…" : "Change…") {
                        viewModel.selectGameFolder()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
                    if viewModel.selectedGameFolder != nil {
                        Button("Clear") { viewModel.selectedGameFolder = nil }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink60)
                    }
                }
            }

            Button("Reset app library to ~/Applications") {
                let url = URL(fileURLWithPath: viewModel.defaultInstallPath)
                    .appendingPathComponent("Applications")
                viewModel.libraryFolder = url
                viewModel.loadLibrary()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(SeleneTheme.ink60)
        }
    }

    // MARK: - Compatibility

    private var compatibilityPanel: some View {
        SelenePanel("Compatibility") {
            sectionHeader(icon: "checkmark.shield.fill",
                          title: "Build gate",
                          detail: viewModel.canPassToolchainGate
                            ? "The pinned engine and Metal compiler match."
                            : "Builds stay blocked until the toolchain matches or you enable the override.",
                          ok: viewModel.canPassToolchainGate)

            if let report = viewModel.compatibilityReport {
                VStack(spacing: 8) {
                    ForEach(report.checks, id: \.id) { check in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: symbol(for: check.status))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(color(for: check.status))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(SeleneTheme.ink.opacity(0.9))
                                Text(check.detail)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(SeleneTheme.ink60)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Running the compatibility check…")
                        .font(.system(size: 11))
                        .foregroundColor(SeleneTheme.ink90)
                }
            }

            HStack(spacing: 10) {
                Button("Re-check") { viewModel.detectEnvironment() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
                if viewModel.compatibilityReport?.ok == false {
                    Button("Review in Settings") {
                        NotificationCenter.default.post(name: .nxLibraryOpenSettings, object: nil)
                        viewModel.showSetupSheet = false
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.untested)
                }
                Spacer()
            }
        }
    }

    // MARK: - Import

    private var importPanel: some View {
        SelenePanel("Import") {
            sectionHeader(icon: "square.and.arrow.down.fill",
                          title: "Existing builds",
                          detail: "Imported apps are playable immediately; rebuilds still need their sources.",
                          ok: !viewModel.importedApps.isEmpty)

            if viewModel.isScanningLibrary {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning the app library…")
                        .font(.system(size: 11))
                        .foregroundColor(SeleneTheme.ink90)
                }
            } else if viewModel.importedApps.isEmpty {
                Text("No nxnative app found yet. You can add games later from Add Game.")
                    .font(.system(size: 11))
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.importedApps) { app in
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundColor(SeleneTheme.success)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(SeleneTheme.ink.opacity(0.92))
                                    .lineLimit(1)
                                Text("\(app.titleId ?? "no title ID") · v\(app.version ?? "?") · \(seleneBytes(app.sizeBytes))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(SeleneTheme.ink60)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Scan Again") { viewModel.importExistingBuilds() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
            }
        }
    }

    // MARK: - Footer

    private func footer(_ metrics: SeleneLayoutMetrics) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.canCompleteSetup ? SeleneTheme.success : SeleneTheme.untested)
                .frame(width: 6, height: 6)
            Text(viewModel.canCompleteSetup ? "Setup checks passed." : setupHint)
                .font(.system(size: 11))
                .foregroundColor(viewModel.canCompleteSetup ? SeleneTheme.success : SeleneTheme.untested)
            Spacer()
            SeleneActionButton(title: "Finish Setup", kind: .primary,
                               isEnabled: viewModel.canCompleteSetup) {
                viewModel.completeSetup()
                dismiss()
            }
        }
        .padding(.horizontal, metrics.margin)
        .padding(.vertical, 16)
        .background(SeleneTheme.glassSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(SeleneTheme.ink15).frame(height: 1)
        }
    }

    private var setupHint: String {
        if !viewModel.isNxnativeValid { return "The nxnative checkout is missing." }
        if !viewModel.isProdKeysValid { return "Import a valid prod.keys file." }
        if viewModel.environmentStatus?.canBuild != true { return "The build environment is incomplete." }
        if viewModel.libraryFolder == nil { return "Choose an app library folder." }
        return "Complete the checks above to continue."
    }

    // MARK: - Components

    private func sectionHeader(icon: String, title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SeleneTheme.ink.opacity(0.055))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink.opacity(0.95))
                    Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ok ? SeleneTheme.success : SeleneTheme.untested)
                }
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundColor(SeleneTheme.ink60.opacity(0.7))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(SeleneTheme.ink.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(SeleneTheme.ink.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(SeleneTheme.untested)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(SeleneTheme.untested)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func statusPill(ok: Bool, on: String, off: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? SeleneTheme.success : SeleneTheme.untested)
                .frame(width: 5, height: 5)
            Text(ok ? on : off)
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundColor(ok ? SeleneTheme.success : SeleneTheme.untested)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((ok ? SeleneTheme.success : SeleneTheme.untested).opacity(0.1))
        .overlay(Capsule().strokeBorder((ok ? SeleneTheme.success : SeleneTheme.untested).opacity(0.26), lineWidth: 1))
        .clipShape(Capsule())
    }

    private func symbol(for status: CheckStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .block: return "xmark.circle.fill"
        }
    }

    private func color(for status: CheckStatus) -> Color {
        switch status {
        case .pass: return SeleneTheme.success
        case .warn: return SeleneTheme.untested
        case .block: return SeleneTheme.danger
        }
    }
}

private struct SetupStep: Identifiable {
    let id: String
    let number: Int
    let title: String
    let isComplete: Bool
    let isCurrent: Bool
}
