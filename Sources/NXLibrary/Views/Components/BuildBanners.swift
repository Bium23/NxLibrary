import SwiftUI

public struct BuildBanners: View {
    @ObservedObject public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Setup Quick-Fix Banners
            BuildPrerequisiteBanners(viewModel: viewModel)
            
            // Success & Error Banners
            if let successPath = viewModel.buildSuccessPath {
                successBanner(path: successPath)
            }
            
            if let error = viewModel.buildError {
                errorBanner(message: error)
            }
        }
    }
    
    // MARK: - Banner Subviews
    
    private func successBanner(path: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(Color(red: 0.13, green: 0.77, blue: 0.37))
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Game Port Succeeded!")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(NXTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Button("View in Library") {
                viewModel.selectedTab = 0
            }
            .buttonStyle(NXSecondaryButtonStyle())
            
            Button("Reveal in Finder") {
                viewModel.openOutputInFinder()
            }
            .buttonStyle(NXPrimaryButtonStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.4), lineWidth: 1)
        )
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 24))
                .foregroundColor(Color.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Build Failed")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(NXTheme.textPrimary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("View Logs") {
                viewModel.selectedTab = 4
            }
            .buttonStyle(NXSecondaryButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
        )
    }
}
