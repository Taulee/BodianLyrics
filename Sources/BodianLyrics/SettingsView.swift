import AppKit
import BodianCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PlaybackModel
    @State private var registrationError = ""
    @State private var showsRegistrationError = false
    @State private var isRestartingBackground = false

    private var p: Preferences { model.preferences }
    private var b: Binding<Preferences> { $model.preferences }

    var body: some View {
        TabView {
            general.tabItem { Label(p.label("通用", "General"), systemImage: "gearshape") }
            menu.tabItem { Label(p.label("状态栏", "Menu Bar"), systemImage: "menubar.rectangle") }
        }
        .padding(14)
        .frame(minWidth: 565, minHeight: 620)
        .alert(p.label("无法启用歌词后台", "Could not enable the lyrics service"),
               isPresented: $showsRegistrationError) {
            Button(p.label("好", "OK"), role: .cancel) {}
        } message: {
            Text(registrationError)
        }
    }

    private var general: some View {
        Form {
            Section(p.label("歌词后台", "Lyrics service")) {
                if isRestartingBackground || model.backgroundStatus == .enabled {
                    Button(isRestartingBackground
                           ? p.label("正在重启歌词后台…", "Restarting Lyrics Service…")
                           : p.label("重启歌词后台", "Restart Lyrics Service")) {
                        restartBackground()
                    }
                    .disabled(isRestartingBackground)
                } else if model.backgroundStatus == .requiresApproval {
                    Text(p.label("请在系统设置中允许波点歌词在后台运行。",
                                 "Allow Bodian Lyrics to run in the background in System Settings."))
                    Button(p.label("打开登录项设置", "Open Login Items Settings")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } else {
                    Text(p.label("歌词后台读取本地歌词，并可在你打开波点音乐时唤起歌词界面。",
                                 "The lyrics service reads local lyrics and can open the display when Bodian Music launches."))
                    Button(p.label("启用歌词后台", "Enable Lyrics Service")) {
                        do {
                            try model.enableBackgroundService()
                        } catch {
                            showBackgroundError(error)
                        }
                    }
                }
            }
            Section(p.label("应用", "App")) {
                Picker(p.label("语言", "Language"), selection: b.language) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
                toggle("随波点音乐启动", "Launch with Bodian Music", b.followLaunch)
                toggle("随波点音乐退出", "Quit with Bodian Music", b.followQuit)
            }
            Section(p.label("歌词排版", "Lyric layout")) {
                toggle("长句拆分", "Split long lines", b.splitLongLines)
                toggle("短句合并", "Merge short lines", b.mergeShortLines)
            }
            Section(p.label("歌词同步", "Lyric sync")) {
                HStack {
                    Text(p.label("全局时间偏移", "Global timing offset"))
                    Spacer()
                    offsetControls(model.globalLyricOffset, adjust: model.adjustGlobalLyricOffset)
                }
            }
            Section(p.label("当前歌曲", "Current track")) {
                LabeledContent(p.label("歌名", "Title"), value: model.playback.track?.title ?? "—")
                LabeledContent(p.label("本地歌词", "Local lyrics"),
                               value: !model.layout.lines.isEmpty
                               ? p.label("已解析", "Parsed") : p.label("等待波点缓存", "Waiting for Bodian cache"))
                HStack {
                    Text(p.label("歌词时间偏移", "Lyric timing offset"))
                    Spacer()
                    if let offset = model.lyricOffset {
                        offsetControls(offset, adjust: model.adjustLyricOffset)
                    } else {
                        Text(p.label("等待识别歌曲", "Waiting to identify a song")).foregroundStyle(.secondary)
                    }
                }
                Button(p.label("打开已解码歌词文件夹", "Open decoded lyrics folder")) {
                    openDecodedLyrics()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func offsetControls(_ offset: Int, adjust: @escaping (LyricOffsetAction) -> Void) -> some View {
        Text(p.offsetLabel(offset)).monospacedDigit().foregroundStyle(.secondary)
        ForEach(LyricOffsetAction.allCases, id: \.self) { action in
            Button(action.title(p)) { adjust(action) }
                .disabled(action == .reset && offset == 0)
        }
    }

    private func restartBackground() {
        isRestartingBackground = true
        Task {
            defer { isRestartingBackground = false }
            do {
                try await model.restartBackgroundService()
            } catch {
                showBackgroundError(error)
            }
        }
    }

    private func showBackgroundError(_ error: Error) {
        guard model.backgroundStatus != .requiresApproval else { return }
        registrationError = error.localizedDescription
        showsRegistrationError = true
    }

    private var menu: some View {
        VStack(spacing: 4) {
            menuPreview
            Form {
                Section(p.label("歌词外观", "Lyric appearance")) {
                    fontPicker(b.menuFontFamily)
                    picker("字重", "Weight", b.menuFontWeight, weights)
                    fontSizeSlider
                    picker("对齐", "Alignment", b.menuAlignment, alignments)
                    positionControls
                    slider("显示宽度（pt）", "Display width (pt)", b.menuWidth, 80...550)
                    toggle("固定宽度", "Fixed width", b.menuFixedWidth)
                    Text(p.label("关闭时按每首歌的最长显示行分配宽度，换歌时可改变。开启时每首歌都占用设定宽度。",
                                 "When off, the width fits each song’s longest displayed line and may change between songs. When on, every song uses the configured width."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    toggle("逐字高亮", "Karaoke highlighting", b.menuKaraoke)
                    color("未唱颜色", "Base color", b.menuTextColor)
                    color("已唱颜色", "Fill color", b.menuFillColor)
                    integer("最大歌词字符数", "Maximum lyric characters", b.menuMaxCharacters, 10...160)
                    Text(p.label("字符数决定每句保留多少字，显示宽度决定文字能占多宽。长句超宽时会滚动。",
                                 "The character limit caps each lyric line. The display width caps the space it can use. Lines that exceed the width scroll."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var alignments: [(AlignmentChoice, String, String)] {
        [(.center, "文字居中", "Center text"), (.trailing, "右对齐", "Right align")]
    }

    private func openDecodedLyrics() {
        Task {
            do {
                let folder = BodianFiles.parsed
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                _ = try await NSWorkspace.shared.open(folder, configuration: .init())
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private var weights: [(WeightChoice, String, String)] {
        [(.regular, "常规", "Regular"), (.medium, "中等", "Medium"), (.semibold, "半粗", "Semibold"), (.bold, "粗体", "Bold")]
    }

    private func toggle(_ zh: String, _ en: String, _ value: Binding<Bool>) -> some View {
        Toggle(p.label(zh, en), isOn: value)
    }

    private func picker<Value: Hashable>(_ zh: String, _ en: String, _ value: Binding<Value>,
                                         _ choices: [(Value, String, String)]) -> some View {
        Picker(p.label(zh, en), selection: value) {
            ForEach(choices, id: \.0) { choice in
                Text(p.label(choice.1, choice.2)).tag(choice.0)
            }
        }
    }

    private func slider(_ zh: String, _ en: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        let roundedValue = Binding(get: { value.wrappedValue }, set: { newValue in
            let rounded = newValue.rounded()
            if rounded != value.wrappedValue { value.wrappedValue = rounded }
        })
        return LabeledContent(p.label(zh, en)) {
            Slider(value: roundedValue, in: range).frame(width: 135)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))
                .monospacedDigit().frame(width: 32, alignment: .trailing)
        }
    }

    private var fontSizeSlider: some View {
        let midpoint = Preferences.menuBarFontSize
        let radius = min(9, midpoint - 1)
        let size = midpoint.formatted(.number.precision(.fractionLength(0...1)))
        return slider("字号（pt）", "Font size (pt)", b.menuFontSize, (midpoint - radius)...(midpoint + radius))
            .help(p.label("滑块中点为系统菜单栏字号 \(size) pt", "The midpoint is the system menu bar size, \(size) pt"))
    }

    private var positionControls: some View {
        let position = p.menuPosition ?? MenuPosition()
        return HStack {
            Text(p.label("文字位置微调", "Text position"))
            Spacer()
            Text("X \(position.x) · Y \(position.y)").monospacedDigit().foregroundStyle(.secondary)
            positionButton("向左", "Move left", icon: "arrow.left", x: -1, y: 0)
            positionButton("向右", "Move right", icon: "arrow.right", x: 1, y: 0)
            positionButton("向上", "Move up", icon: "arrow.up", x: 0, y: -1)
            positionButton("向下", "Move down", icon: "arrow.down", x: 0, y: 1)
            Button(p.label("重置", "Reset")) { model.preferences.menuPosition = nil }
                .disabled(position == MenuPosition())
        }
    }

    private func positionButton(_ zh: String, _ en: String, icon: String, x: Int, y: Int) -> some View {
        let current = p.menuPosition ?? MenuPosition()
        let next = MenuPosition(x: current.x + x, y: current.y + y)
        let title = p.label(zh, en)
        return Button { model.preferences.menuPosition = next } label: {
            Image(systemName: icon)
        }
        .accessibilityLabel(title)
        .help(title)
        .disabled(abs(next.x) > MenuPosition.horizontalLimit || abs(next.y) > MenuPosition.verticalLimit)
    }

    private func integer(_ zh: String, _ en: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(p.label(zh, en), value: String(value.wrappedValue))
        }
    }

    private func color(_ zh: String, _ en: String, _ value: Binding<String>) -> some View {
        LabeledContent(p.label(zh, en)) {
            ColorPicker(p.label(zh, en), selection: Binding(
                get: { hexColor(value.wrappedValue) ?? .primary },
                set: { value.wrappedValue = rgbHex($0) }), supportsOpacity: false)
            .labelsHidden()
            Button(p.label("默认", "Default")) { value.wrappedValue = "" }
        }
    }

    private func fontPicker(_ value: Binding<String>) -> some View {
        FontFamilyPicker(selection: value, preferences: p)
    }

    private var menuPreview: some View {
        MenuBarView(model: model, preview: true)
            .padding(6)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .accessibilityLabel(p.label("效果预览", "Preview"))
    }
}

private struct FontFamilyPicker: View {
    @Binding var selection: String
    let preferences: Preferences
    @State private var isPresented = false
    @State private var search = ""

    private static let families = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }

    var body: some View {
        let title = preferences.label("字体", "Font")
        return HStack {
            Text(title)
            Spacer()
            Button {
                search = ""
                isPresented = true
            } label: {
                HStack {
                    fontName(selection)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }
            .accessibilityLabel(title)
            .accessibilityValue(selection.isEmpty ? preferences.label("系统字体", "System font") : selection)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    TextField(preferences.label("搜索字体", "Search fonts"), text: $search)
                        .textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if search.isEmpty { option("") }
                            ForEach(Self.families.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) {
                                option($0)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(width: 280, height: 320)
            }
        }
    }

    private func option(_ family: String) -> some View {
        Button {
            selection = family
            isPresented = false
        } label: {
            HStack {
                fontName(family)
                Spacer()
                if selection == family { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == family ? .isSelected : [])
    }

    private func fontName(_ family: String) -> Text {
        let title = family.isEmpty ? preferences.label("系统字体", "System font") : family
        return Text(verbatim: title)
            .font(Font(lyricFont(family: family, size: NSFont.systemFontSize, weight: .regular)))
    }
}
