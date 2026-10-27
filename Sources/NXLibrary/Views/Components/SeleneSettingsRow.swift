import SwiftUI

public struct SeleneRow<Trailing: View>: View {
    public let title: String
    public let subtitle: String?
    @ViewBuilder public var trailing: () -> Trailing

    public init(_ title: String, subtitle: String? = nil,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SeleneTheme.ink.opacity(0.94))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(SeleneTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(SeleneTheme.surface.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous)
                .strokeBorder(SeleneTheme.border.opacity(0.85), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous))
    }
}

public struct SeleneToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.13))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? SeleneTheme.canvas : Color.white)
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .animation(SeleneTheme.quick, value: configuration.isOn)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

public struct SeleneToggleRow: View {
    public let title: String
    public let subtitle: String?
    @Binding public var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        SeleneRow(title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SeleneToggleStyle())
        }
    }
}

public struct SeleneValueRow: View {
    public let title: String
    public let subtitle: String?
    public let value: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(_ title: String, subtitle: String? = nil, value: String,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        SeleneRow(title, subtitle: subtitle) {
            HStack(spacing: 10) {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SeleneTheme.ink.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.accent)
                }
            }
        }
    }
}

public struct SeleneButtonRow: View {
    public let title: String
    public let subtitle: String?
    public let buttonTitle: String
    public let action: () -> Void

    public init(_ title: String, subtitle: String? = nil,
                buttonTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.action = action
    }

    public var body: some View {
        SeleneRow(title, subtitle: subtitle) {
            Button(buttonTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SeleneTheme.accent)
        }
    }
}

public struct SeleneSegmented<Value: Hashable>: View {
    @Binding public var selection: Value
    public let options: [(Value, String)]

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(selection == option.0 ? SeleneTheme.canvas : SeleneTheme.ink.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selection == option.0 ? SeleneTheme.focus : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(SeleneTheme.ink.opacity(0.055))
        .overlay(Capsule().strokeBorder(SeleneTheme.border, lineWidth: 1))
        .clipShape(Capsule())
    }
}

public struct SelenePanel<Content: View>: View {
    public let title: String?
    @ViewBuilder public var content: () -> Content

    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundColor(SeleneTheme.inkMuted)
            }
            content()
        }
        .padding(16)
        .background(SeleneTheme.canvasRaised)
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous)
                .strokeBorder(SeleneTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.cardRadius, style: .continuous))
    }
}
