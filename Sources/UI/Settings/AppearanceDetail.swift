import Defaults
import SwiftUI

struct AppearanceDetail: View {
    @Default(.skin) private var skin
    @Default(.theme) private var theme
    @Default(.showMetricText) private var showMetricText
    @Default(.externalSkinPath) private var externalSkinPath
    private let skinManager = SkinManager.shared

    var body: some View {
        Form {
            Section {
                GlassEffectContainer {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)], spacing: 10) {
                    ForEach(skinManager.allSkins) { s in
                        Button {
                            skin = s.id
                        } label: {
                            SkinThumbnail(skin: s, isSelected: skin == s.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                }
            } header: {
                Text("皮肤")
            }

            Section {
                Picker(selection: $theme, label: Label("外观模式", systemImage: "circle.lefthalf.filled")) {
                    ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                        Text("\(mode.emoji) \(mode.displayName)").tag(mode)
                    }
                }
            } header: {
                Text("主题")
            }

            Section {
                Toggle(isOn: $showMetricText) {
                    Label("显示数值文字", systemImage: "percent")
                }
            } header: {
                Text("菜单栏")
            } footer: {
                Text("在菜单栏图标旁显示当前指标百分比。")
            }

            Section {
                HStack {
                    TextField("路径", text: $externalSkinPath, prompt: Text("~/skins"))
                        .textFieldStyle(.roundedBorder)
                    Button("浏览") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            externalSkinPath = url.path
                        }
                    }
                }
                if !externalSkinPath.isEmpty {
                    let expanded = (externalSkinPath as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: expanded) {
                        Text("目录下的皮肤文件夹会自动加载，同名会覆盖内置皮肤")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Label("路径不存在", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("外部皮肤")
            }
        }
        .formStyle(.grouped)
        .onChange(of: externalSkinPath) {
            SkinManager.shared.reload()
        }
    }
}
