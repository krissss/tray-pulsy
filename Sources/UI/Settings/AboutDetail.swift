import SwiftUI

struct AboutDetail: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .padding(8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RunCatX")
                            .font(.title2.bold())
                        Text("版本 0.3.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                AboutRow(icon: "person.fill", label: "开发者", value: "krissss")
                AboutRow(icon: "paintbrush.fill", label: "风格", value: "菜单栏猫咪动画")
                AboutRow(icon: "lightbulb.fill", label: "灵感来源", value: "Kyome22 / RunCat365")
            } header: {
                Text("信息")
            }

            Section {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 RunCatX", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
    }
}
