import SwiftUI

public struct CommandHint: Identifiable, Equatable {
    public let id: String
    public let key: String
    public let label: String
    public init(_ key: String, _ label: String) {
        self.id = key + ":" + label
        self.key = key
        self.label = label
    }
}

public struct CommandBar: View {
    public let hints: [CommandHint]
    public init(_ hints: [CommandHint]) { self.hints = hints }

    public var body: some View {
        HStack(spacing: 22) {
            ForEach(hints) { hint in
                HStack(spacing: 6) {
                    Text(hint.key)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SeleneTheme.canvas)
                        .frame(width: 18, height: 18)
                        .background(SeleneTheme.focus.opacity(0.92))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    Text(hint.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SeleneTheme.ink.opacity(0.86))
                        .shadow(color: .black.opacity(0.65), radius: 4, y: 1)
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
