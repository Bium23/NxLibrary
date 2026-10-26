import SwiftUI

public struct BuildBanners: View {
    @ObservedObject public var viewModel: AppViewModel
    @Binding public var isCreditsDismissed: Bool
    
    public init(viewModel: AppViewModel, isCreditsDismissed: Binding<Bool>) {
        self.viewModel = viewModel
        self._isCreditsDismissed = isCreditsDismissed
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Upstream Developer Credits & Notice
            if !isCreditsDismissed {
                creditsBanner
            }
            
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
    
    private var creditsBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 24))
                .foregroundColor(NXTheme.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("nxnative by @seedds")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(NXTheme.textPrimary)
                    
                    Link("GitHub Repository ↗", destination: URL(string: "https://github.com/seedds/nxnative")!)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(NXTheme.secondary)
                }
                
                Text("This community GUI is a helper tool to make porting Switch games accessible without terminal commands. Notice: As soon as the upstream developer releases an official launcher, this project will be deprecated in favor of the official release.")
                    .font(.system(size: 11))
                    .foregroundColor(NXTheme.textSecondary)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    isCreditsDismissed = true
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(NXTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NXTheme.primary.opacity(0.12))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NXTheme.primary.opacity(0.35), lineWidth: 1)
        )
    }
    
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
