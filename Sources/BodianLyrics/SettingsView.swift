import AppKit
import BodianCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PlaybackModel

    private var p: Preferences { model.preferences }
    private var b: Binding<Preferences> { $model.preferences }

    var body: some View {
        TabView {
            general.tabItem { Label(p.label("通用", "General"), systemImage: "gearshape") }
            menu.tabItem { Label(p.label("状态栏", "Menu Bar"), systemImage: "menubar.rectangle") }
            island.tabItem { Label(p.label("灵动岛", "Dynamic Island"), systemImage: "rectangle.topthird.inset.filled") }
        }
        .padding(14)
        .frame(minWidth: 565, minHeight: 620)
    }

    private var general: some View {
        Form {
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
            Section(p.label("当前歌曲", "Current track")) {
                LabeledContent(p.label("歌名", "Title"), value: model.playback.track?.title ?? "—")
                LabeledContent(p.label("本地歌词", "Local lyrics"),
                               value: model.layouts[.island]?.lines.isEmpty == false
                               ? p.label("已解析", "Parsed") : p.label("等待波点缓存", "Waiting for Bodian cache"))
            }
        }
        .formStyle(.grouped)
    }

    private var menu: some View {
        VStack(spacing: 4) {
            preview(.menu)
            Form {
                Section(p.label("歌词外观", "Lyric appearance")) {
                    toggle("显示状态栏歌词", "Show menu bar lyrics", b.menuEnabled)
                    fontPicker(b.menuFontFamily)
                    picker("字重", "Weight", b.menuFontWeight, weights)
                    slider("字号（0 为默认）", "Font size (0 for default)", b.menuFontSize, 0...22)
                    picker("对齐", "Alignment", b.menuAlignment, alignments)
                    slider("歌词宽度", "Lyric width", b.menuWidth, 80...550)
                    toggle("固定宽度", "Fixed width", b.menuFixedWidth)
                    toggle("逐字高亮", "Karaoke highlighting", b.menuKaraoke)
                    toggle("彩虹歌词", "Rainbow lyrics", b.menuRainbow)
                    color("未唱颜色", "Base color", b.menuTextColor)
                    color("已唱颜色", "Fill color", b.menuFillColor)
                    picker("声波位置", "Waveform position", b.menuIconPosition,
                           [(.leading, "左侧", "Leading"), (.trailing, "右侧", "Trailing"), (.off, "关闭", "Off")])
                    picker("声波大小", "Waveform size", b.menuIconSize,
                           [(.small, "小", "Small"), (.standard, "标准", "Standard"), (.large, "大", "Large")])
                    toggle("声波动画", "Animate waveform", b.menuIconAnimates)
                }
                Section(p.label("显示行为", "Display behavior")) {
                    picker("显示内容", "Content", b.menuContent,
                           [(.lyrics, "歌词", "Lyrics"), (.translation, "译文", "Translation"),
                            (.title, "歌名", "Title"), (.titleArtist, "歌名与歌手", "Title and artist")])
                    picker("副行", "Secondary line", b.menuSecondary,
                           secondary + [(.inlineTranslation, "译文（同一行）", "Inline translation")])
                    toggle("无歌词时显示歌名", "Show title without lyrics", b.menuTitleWithoutLyrics)
                    integer("最大字符数", "Maximum characters", b.menuMaxCharacters, 10...160)
                    toggle("在状态栏中央显示", "Center lyrics in menu bar", b.menuCentered)
                    if p.menuCentered { screenPicker(b.menuScreen, allLabel: true) }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var island: some View {
        VStack(spacing: 4) {
            HStack {
                preview(.island)
                preview(.expanded)
            }
            Form {
                Section(p.label("歌词外观", "Lyric appearance")) {
                    toggle("显示灵动岛", "Show Dynamic Island", b.islandEnabled)
                    toggle("显示歌词行", "Show lyric row", b.islandShowLyrics)
                    fontPicker(b.islandFontFamily)
                    picker("字重", "Weight", b.islandFontWeight, weights)
                    slider("字号", "Font size", b.islandFontSize, 9...30)
                    slider("行高", "Row height", b.islandRowHeight, 20...62)
                    picker("对齐", "Alignment", b.islandAlignment,
                           [(nil, "自动", "Automatic")] + alignments.map { (Optional($0.0), $0.1, $0.2) })
                    picker("歌词颜色", "Lyric color", b.islandColor,
                           [(.accent, "强调色", "Accent"), (.rainbow, "彩虹", "Rainbow")])
                    toggle("逐字高亮", "Karaoke highlighting", b.islandKaraoke)
                    picker("副行", "Secondary line", b.islandSecondary, secondary)
                    picker("背景", "Background", b.islandStyle, styles)
                    picker("展开背景", "Expanded background", b.islandExpandedStyle,
                           [(nil, "跟随普通背景", "Match compact")] + styles.map { (Optional($0.0), $0.1, $0.2) })
                    slider("宽度", "Width", b.islandWidth, 180...650)
                    slider("展开宽度", "Expanded width", b.islandExpandedWidth, 280...850)
                    slider("圆角（−1 为自动）", "Corner radius (−1 for auto)", b.islandCorner, -1...32)
                    slider("展开圆角（−1 为自动）", "Expanded radius (−1 for auto)", b.islandExpandedCorner, -1...44)
                    picker("左耳内容", "Left ear", b.islandLeftEar, ears)
                    picker("右耳内容", "Right ear", b.islandRightEar, ears)
                    toggle("显示音浪", "Show waveform", b.islandEqualizer)
                    if p.islandEqualizer { picker("音浪位置", "Waveform side", b.islandEqualizerSide, sides) }
                    toggle("歌词行显示封面", "Show artwork beside lyrics", b.islandLyricArtwork)
                    if p.islandLyricArtwork { picker("封面位置", "Artwork side", b.islandLyricArtworkSide, sides) }
                    picker("进度线", "Progress line", b.islandProgress,
                           [(.ears, "沿外沿", "Outline"), (.bottom, "底边", "Bottom"), (.off, "关闭", "Off")])
                }
                Section(p.label("展开内容", "Expanded content")) {
                    toggle("显示封面", "Show artwork", b.islandExpandedArtwork)
                    toggle("显示歌名", "Show title", b.islandExpandedTitle)
                    toggle("显示歌手", "Show artist", b.islandExpandedArtist)
                    toggle("显示专辑", "Show album", b.islandExpandedAlbum)
                    toggle("显示下一句", "Show next line", b.islandExpandedNextLine)
                    toggle("显示歌词列表", "Show lyric list", b.islandExpandedLyricList)
                    if p.islandExpandedLyricList {
                        integer("歌词列表行数", "Lyric list rows", b.islandListLines, 3...9)
                    }
                    toggle("显示歌词偏移", "Show lyric offset", b.islandExpandedOffset)
                }
                Section(p.label("显示行为", "Display behavior")) {
                    toggle("全屏时隐藏", "Hide in full screen", b.islandHideFullScreen)
                    toggle("截图与录屏时隐藏", "Exclude from screen capture", b.islandHideInCapture)
                    toggle("未播放时隐藏", "Hide when paused", b.islandHideWhenPaused)
                    toggle("暂停时收起", "Collapse when paused", b.islandCollapseWhenPaused)
                    toggle("无歌词时收起", "Collapse without lyrics", b.islandCollapseWithoutLyrics)
                    toggle("悬停时淡化歌词", "Fade lyrics on hover", b.islandFadeOnHover)
                    toggle("换歌时显示歌名", "Show title on track change", b.islandTrackDrop)
                    toggle("启用滚动展开与收起", "Expand and collapse with scroll", b.islandGestures)
                    toggle("锁屏时显示", "Show on lock screen", b.islandLockScreen)
                    toggle("在所有屏幕显示", "Show on all displays", b.islandAllScreens)
                    if !p.islandAllScreens {
                        toggle("跟随当前窗口所在屏幕", "Follow active window", b.islandFollowActive)
                        if !p.islandFollowActive { screenPicker(b.islandScreen) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var alignments: [(AlignmentChoice, String, String)] {
        [(.leading, "左对齐", "Leading"), (.center, "居中", "Centered"), (.trailing, "右对齐", "Trailing")]
    }

    private var weights: [(WeightChoice, String, String)] {
        [(.regular, "常规", "Regular"), (.medium, "中等", "Medium"), (.semibold, "半粗", "Semibold"), (.bold, "粗体", "Bold")]
    }

    private var secondary: [(SecondaryLine, String, String)] {
        [(.nextLine, "下一句", "Next line"), (.translation, "译文", "Translation"), (.off, "关闭", "Off")]
    }

    private var styles: [(IslandStyle, String, String)] {
        [(.solidBlack, "纯黑", "Black"), (.frostedGlass, "磨砂玻璃", "Frosted glass"),
         (.darkGradient, "深色渐变", "Dark gradient"), (.coverArt, "封面取色", "Artwork tint")]
    }

    private var sides: [(Side, String, String)] { [(.left, "左侧", "Left"), (.right, "右侧", "Right")] }

    private var ears: [(EarContent, String, String)] {
        [(.none, "留空", "None"), (.artwork, "封面", "Artwork"), (.title, "歌名", "Title"),
         (.artist, "歌手", "Artist"), (.album, "专辑", "Album"), (.elapsed, "已播放", "Elapsed"),
         (.remaining, "剩余", "Remaining"), (.player, "波点音乐", "Bodian Music")]
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
        LabeledContent(p.label(zh, en)) {
            Slider(value: value, in: range, step: 1).frame(width: 135)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))
                .monospacedDigit().frame(width: 32, alignment: .trailing)
        }
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
        Picker(p.label("字体", "Font"), selection: value) {
            Text(p.label("系统字体", "System font")).tag("")
            ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) }
        }
    }

    private func screenPicker(_ value: Binding<String>, allLabel: Bool = false) -> some View {
        Picker(p.label("屏幕", "Display"), selection: value) {
            Text(allLabel ? p.label("所有屏幕", "All displays") : p.label("默认屏幕", "Default display")).tag("")
            ForEach(NSScreen.screens, id: \.localizedName) { screen in
                if let id = ScreenIdentity.id(of: screen) { Text(screen.localizedName).tag(id) }
            }
        }
    }

    private func preview(_ surface: Surface) -> some View {
        SurfaceView(model: model, surface: surface, preview: true)
            .frame(width: surface == .menu ? nil : 245)
            .frame(height: surface == .menu ? 28 : 136, alignment: .top)
            .clipped()
            .padding(6)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .accessibilityLabel(p.label("效果预览", "Preview"))
    }
}
