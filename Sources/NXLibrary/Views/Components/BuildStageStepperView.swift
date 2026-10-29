import SwiftUI

public struct BuildStageStepperView: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Build stages")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink90)
                Spacer()
                Text("\(viewModel.stageIndex)/\(max(viewModel.totalStages, viewModel.buildStages.count))")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(SeleneTheme.ink60)
            }

            VStack(spacing: 7) {
                ForEach(viewModel.buildStages) { stage in
                    stageRow(stage)
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

    private func stageRow(_ stage: BuildStageItem) -> some View {
        HStack(spacing: 9) {
            Group {
                if stage.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else if stage.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SeleneTheme.success)
                        .font(.system(size: 13))
                } else if stage.isFailed {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SeleneTheme.danger)
                        .font(.system(size: 13))
                } else {
                    Circle()
                        .strokeBorder(SeleneTheme.ink60.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 16)

            Text("Stage \(stage.id): \(stage.name)")
                .font(.system(size: 11, weight: stage.isRunning ? .semibold : .regular))
                .foregroundColor(stage.isRunning ? SeleneTheme.ink
                                 : (stage.isCompleted ? SeleneTheme.ink90 : SeleneTheme.ink60))

            if !stage.step.isEmpty, stage.isRunning {
                Text(stage.step)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SeleneTheme.glyph)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let elapsed = stage.elapsedSeconds, elapsed > 0 {
                Text(String(format: "%.1fs", elapsed))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(SeleneTheme.ink60)
            }
        }
        .padding(.vertical, 1)
    }
}
