import SwiftUI

struct AboutDetail: View {
    var body: some View {
        GlassEffectContainer {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .padding(8)
                            .glassEffect(in: .rect(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppConstants.appName)
                                .font(.title2.bold())
                            Text(String(format: L10n.aboutVersion, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    AboutLinkRow(icon: "person.fill", label: L10n.aboutDeveloper, value: "kriss", url: "https://github.com/krissss")
                    AboutLinkRow(icon: "chevron.left.forwardslash.chevron.right", label: "GITHUB", value: "GitHub", url: "https://github.com/krissss/tray-pulsy")
                    AboutLinkRow(icon: "lightbulb.fill", label: L10n.aboutInspiration, value: "RunCat365", url: "https://github.com/Kyome22/RunCat365")
                } header: {
                    Text(L10n.aboutInfoHeader)
                }

                Section {
                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label(String(format: L10n.aboutQuit, AppConstants.appName), systemImage: "power")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct AboutLinkRow: View {
    let icon: String
    let label: String
    let value: String
    let url: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Link(value, destination: URL(string: url)!)
        }
    }
}
