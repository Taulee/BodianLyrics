import AppKit
import Combine
import SwiftUI

@main
struct BodianLyricsApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class StatusHost: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PlaybackModel()
    private let activeFollower = ActiveScreenFollower()
    private var activeScreen: NSScreen?
    private var status: NSStatusItem!
    private var settings: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var normalIslands: [String: IslandPanel] = [:]
    private var centeredLyrics: [String: NotchLyricsWindow] = [:]
    private var lockIsland: IslandPanel?
    private var screenLocked = false
    private var quitWork: DispatchWorkItem?
    private var wasRunning = false
    private var menuWidth: CGFloat = 28

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: 28)
        if let button = status.button {
            let content = SurfaceView(model: model, surface: .menu, iconOnly: false)
                .fixedSize(horizontal: true, vertical: false)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { [weak self] width in
                    guard let self else { return }
                    menuWidth = ceil(width)
                    updateStatusWidth()
                }
            let host = StatusHost(rootView: AnyView(content))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            updateStatusContent()
        }

        activeFollower.onFollow = { [weak self] screen in
            self?.activeScreen = screen
            self?.refreshPanels()
        }
        activeFollower.canMove = { [weak self] in
            self?.normalIslands.values.contains { $0.expanded } == false
        }
        model.$preferences.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.preferencesChanged() }
        }.store(in: &subscriptions)
        FullScreenSpaceMonitor.shared.$fullScreenDisplays.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPanels() }
        }.store(in: &subscriptions)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(lockScreen), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(unlockScreen), name: .init("com.apple.screenIsUnlocked"), object: nil)
        preferencesChanged()
        poll()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        activeFollower.update(wanted: model.preferences.islandFollowActive && !model.preferences.islandAllScreens)
        activeFollower.follow()
        refreshPanels()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func poll() {
        let before = model.playback
        model.readPlayback()
        if before.running != model.playback.running || before.track?.playing != model.playback.track?.playing
            || (before.track == nil) != (model.playback.track == nil) {
            refreshPanels()
        }
        if model.playback.running {
            wasRunning = true
            quitWork?.cancel()
            quitWork = nil
        } else if wasRunning && model.preferences.followQuit && quitWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                quitWork = nil
                if !model.playback.running && model.preferences.followQuit && settings?.isVisible != true {
                    NSApp.terminate(nil)
                }
            }
            quitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
    }

    private func preferencesChanged() {
        let p = model.preferences
        let menu = NSMenu()
        menu.addItem(withTitle: p.label("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: p.label("退出波点歌词", "Quit Bodian Lyrics"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        status.button?.setAccessibilityLabel(p.label("波点歌词", "Bodian Lyrics"))
        settings?.title = p.label("波点歌词设置", "Bodian Lyrics Settings")
        activeFollower.update(wanted: p.islandFollowActive && !p.islandAllScreens)
        updateStatusContent()
        refreshPanels()
    }

    private func updateStatusContent() {
        guard let host = status.button?.subviews.first(where: { $0 is StatusHost }) as? StatusHost else { return }
        host.rootView = AnyView(SurfaceView(model: model, surface: .menu, iconOnly: model.preferences.menuCentered)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { [weak self] width in
                guard let self else { return }
                menuWidth = ceil(width)
                updateStatusWidth()
            })
    }

    private func updateStatusWidth() {
        status.length = max(24, menuWidth)
    }

    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = model.preferences.label("波点歌词设置", "Bodian Lyrics Settings")
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func lockScreen() {
        screenLocked = true
        refreshPanels()
    }

    @objc private func unlockScreen() {
        screenLocked = false
        refreshPanels()
    }

    private func refreshPanels() {
        let p = model.preferences
        let screens = NSScreen.screens
        let primary = screens.first
        let islandScreens: [NSScreen]
        if p.islandAllScreens {
            islandScreens = screens
        } else if let screen = (p.islandFollowActive ? activeScreen : ScreenIdentity.screen(withID: p.islandScreen)) ?? primary {
            islandScreens = [screen]
        } else {
            islandScreens = []
        }

        let track = model.playback.track
        let showIsland = p.islandEnabled && track != nil && (!p.islandHideWhenPaused || track?.playing == true)
        let visible = screenLocked || !showIsland ? [] : islandScreens.filter {
            !p.islandHideFullScreen || !FullScreenSpaceMonitor.shared.covers($0)
        }
        let visibleIDs = Set(visible.compactMap(ScreenIdentity.id(of:)))
        for (id, panel) in normalIslands where !visibleIDs.contains(id) {
            panel.window.orderOut(nil)
            normalIslands.removeValue(forKey: id)
        }
        for screen in visible {
            guard let id = ScreenIdentity.id(of: screen) else { continue }
            let panel = normalIslands[id] ?? IslandPanel(model: model, screen: screen, locked: false)
            normalIslands[id] = panel
            panel.update(screen: screen)
        }

        if screenLocked && showIsland && p.islandLockScreen && !p.islandHideInCapture, let primary {
            if lockIsland == nil {
                let panel = IslandPanel(model: model, screen: primary, locked: true)
                if LockScreenSpace.adopt(panel.window) { lockIsland = panel }
            }
            lockIsland?.update(screen: primary)
        } else {
            lockIsland?.window.orderOut(nil)
        }

        let menuScreens = p.menuScreen.isEmpty ? screens : screens.filter { ScreenIdentity.id(of: $0) == p.menuScreen }
        let centered = p.menuEnabled && p.menuCentered && !screenLocked && track?.playing == true ? menuScreens : []
        let centerIDs = Set(centered.compactMap(ScreenIdentity.id(of:)))
        for (id, panel) in centeredLyrics where !centerIDs.contains(id) {
            panel.orderOut(nil)
            centeredLyrics.removeValue(forKey: id)
        }
        for screen in centered {
            guard let id = ScreenIdentity.id(of: screen) else { continue }
            let panel = centeredLyrics[id] ?? makeCenteredPanel()
            centeredLyrics[id] = panel
            let top = screen.auxiliaryTopLeftArea
            let width = min(p.menuWidth + 38, (top?.width ?? screen.frame.width) - 10)
            let center = top.map { $0.maxX - width / 2 - 4 } ?? screen.frame.midX
            let height = top?.height ?? NSStatusBar.system.thickness
            panel.setFrame(NSRect(x: center - width / 2, y: screen.frame.maxY - height,
                                  width: width, height: height), display: true)
            panel.orderFrontRegardless()
        }
    }

    private func makeCenteredPanel() -> NotchLyricsWindow {
        let panel = NotchLyricsWindow(contentRect: .zero)
        panel.appearance = nil
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: SurfaceView(model: model, surface: .menu))
        return panel
    }
}

@MainActor
private final class IslandPanel {
    let window = NotchLyricsWindow(contentRect: .zero)
    private let model: PlaybackModel
    private let locked: Bool
    private var screen: NSScreen
    private var host: NSHostingView<AnyView>!
    private var height: CGFloat = 58
    private var width: CGFloat = 252
    private var collapseWork: DispatchWorkItem?
    private(set) var expanded = false

    init(model: PlaybackModel, screen: NSScreen, locked: Bool) {
        self.model = model
        self.screen = screen
        self.locked = locked
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        window.contentView = host
        window.ignoresMouseEvents = locked
        window.onScrollWheel = { [weak self] event in
            guard let self, model.preferences.islandGestures else { return }
            if event.scrollingDeltaY < -4 { setExpanded(true) }
            if event.scrollingDeltaY > 4 { setExpanded(false) }
        }
        setContent()
        place()
    }

    func update(screen: NSScreen) {
        self.screen = screen
        window.sharingType = model.preferences.islandHideInCapture ? .none : .readWrite
        setContent()
        place()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func setContent() {
        let p = model.preferences
        let top = screen.auxiliaryTopLeftArea
        let notchWidth = top.flatMap { left in screen.auxiliaryTopRightArea.map { $0.minX - left.maxX } } ?? 96
        let topHeight = top?.height ?? NSStatusBar.system.thickness
        let collapsed = !expanded && p.islandCollapseWhenPaused && model.playback.track?.playing != true
        let preferred = expanded ? p.islandExpandedWidth : collapsed ? notchWidth + 74 : p.islandWidth
        width = min(screen.frame.width, max(notchWidth + 64, preferred))
        host.rootView = AnyView(SurfaceView(model: model, surface: expanded ? .expanded : .island,
                                           notchWidth: notchWidth, topHeight: topHeight,
                                           onHover: { [weak self] in self?.hover($0) })
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] measured in
                guard let self, height != ceil(measured) else { return }
                height = ceil(measured)
                place()
            })
    }

    private func hover(_ inside: Bool) {
        collapseWork?.cancel()
        guard !locked else { return }
        let work = DispatchWorkItem { [weak self] in self?.setExpanded(inside) }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.22 : 0.32), execute: work)
    }

    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        expanded = value
        setContent()
        place()
    }

    private func place() {
        let rect = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height,
                          width: width, height: height)
        if window.frame != rect { window.setFrame(rect, display: true) }
    }
}
