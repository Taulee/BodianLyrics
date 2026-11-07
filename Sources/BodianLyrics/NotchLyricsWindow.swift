import AppKit

/// 无边框面板贴在显示器顶边，并且不激活应用。
final class NotchLyricsWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)
        // 需要高于菜单栏，才能贴到刘海所在的区域。
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        // isMovable = false 是为了避开 macOS(Sequoia 起)窗口平铺(Window Tiling)
        // 拖拽时的"可平铺目标"高亮提示:拖动任意窗口经过屏幕顶部时,系统会判断这个
        // 位置上是否有"可以平铺"的窗口、给它蒙一层蓝色高亮,这份判断依据之一是
        // NSWindow.isMovable。这个窗口本来就不允许用户以任何方式移动(位置永远是
        // recomputeGeometry() 算出来贴死在刘海上的,连 isMovableByWindowBackground
        // 都是 false),显式把 isMovable 也关掉——只影响"用户能不能移动这个窗口"
        // (拖标题栏/Option-拖/窗口菜单的"移动"命令),不影响 recomputeGeometry() 里
        // 用的 setFrame(_:display:animate:) 这类程序化定位,把它标成"不可移动"让
        // 系统平铺功能的高亮探测跳过它。
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // 能成为 key,但只在点到真正要键盘的控件时才成为(NSPanel.becomesKeyOnlyIfNeeded)。灵动岛里的按钮都不要键盘:
    // 默认行为下点一下播放键这扇窗就成了 key 窗口,用户在别的 App 里接着敲的字全落到这里丢掉。

    // 保留顶边坐标，避免 AppKit 把面板推到菜单栏下方。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // 将滚动事件交给面板控制器处理展开和收起。
    var onScrollWheel: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { onScrollWheel?(event) }
        super.sendEvent(event)
    }
}
