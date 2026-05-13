import SwiftUI

struct SettingsFormPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer {
            Form {
                content()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 22, for: .scrollContent)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 22, for: .scrollContent)
            .background(.clear)
        }
    }
}

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowIcon(systemImage: systemImage, color: color)

            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

struct SettingsRowIcon: View {
    let systemImage: String
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(color.opacity(0.12), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct SettingsValueBadge: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.11))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.15), lineWidth: 1)
            }
    }
}

struct SettingsInsetPanel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.09), lineWidth: 1)
        }
    }
}

struct SettingsDisclosureButton: View {
    let title: String
    let systemImage: String
    let isExpanded: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(ContainedExpansionMotion.layoutAnimation(expanding: !isExpanded)) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 18)
                    .background {
                        Circle()
                            .fill(.secondary.opacity(0.09))
                    }
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(.rect(cornerRadius: 9, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isExpanded ? color.opacity(0.08) : .secondary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isExpanded ? color.opacity(0.14) : .secondary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(ContainedExpansionMotion.controlAnimation, value: isExpanded)
    }
}
