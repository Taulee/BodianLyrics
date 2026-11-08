import AppKit
import BodianCore
import Combine
import Darwin
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

private final class StatusHost: NSHostingView<MenuBarView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class DirectoryWatcher {
    private let directory: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(_ directory: URL, onChange: @escaping () -> Void) throws {
        self.directory = directory
        self.onChange = onChange
        try start()
    }

    deinit { source?.cancel() }

    private func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO, userInfo: [NSURLErrorKey: directory])
        }
        let watch = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                              eventMask: [.write, .delete, .rename], queue: .main)
        watch.setCancelHandler { close(descriptor) }
        watch.setEventHandler { [weak self] in
            guard let self, let source else { return }
            if !source.data.intersection([.delete, .rename]).isEmpty {
                source.cancel()
                self.source = nil
                do {
                    try start()
                } catch {
                    NSLog("Watch %@: %@", directory.path, error.localizedDescription)
                }
            }
            onChange()
        }
        source = watch
        watch.resume()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = PlaybackModel()
    private var status: NSStatusItem!
    private var settings: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var playbackWatcher: DirectoryWatcher?
    private var lyricsWatcher: DirectoryWatcher?
    private var quitWork: DispatchWorkItem?
    private var wasRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: 28)
        let menu = NSMenu()
        menu.delegate = self
        menuNeedsUpdate(menu)
        status.menu = menu
        if let button = status.button {
            let host = StatusHost(rootView: MenuBarView(model: model, onWidthChange: { [weak self] width in
                guard let self, status.length != width else { return }
                status.length = width
            }))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        model.$preferences.map(\.language).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.preferencesChanged() }
        }.store(in: &subscriptions)
        model.$preferences.map(\.followQuit).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateQuitState() }
        }.store(in: &subscriptions)

        preferencesChanged()
        do {
            playbackWatcher = try DirectoryWatcher(BodianFiles.directory) { [weak self] in self?.reloadPlayback() }
            lyricsWatcher = try DirectoryWatcher(BodianFiles.parsed) { [weak self] in self?.model.readLyrics() }
        } catch {
            NSApp.presentError(error)
        }
        reloadPlayback()
        do {
            try model.updateBackgroundRegistration()
        } catch {
            if model.backgroundStatus != .requiresApproval {
                showSettings()
                NSApp.presentError(error)
                return
            }
        }
        if model.backgroundStatus != .enabled { showSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshBackgroundStatus()
        reloadPlayback()
        model.readLyrics()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func reloadPlayback() {
        model.readPlayback()
        updateQuitState()
    }

    func windowWillClose(_ notification: Notification) {
        updateQuitState()
    }

    private func updateQuitState() {
        if model.playback.running {
            wasRunning = true
        }
        if model.playback.running || !model.preferences.followQuit {
            quitWork?.cancel()
            quitWork = nil
        } else if wasRunning && quitWork == nil {
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
        status.button?.setAccessibilityLabel(p.label("波点歌词", "Bodian Lyrics"))
        settings?.title = p.label("波点歌词设置", "Bodian Lyrics Settings")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let p = model.preferences
        menu.removeAllItems()
        menu.addItem(withTitle: p.label("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        let offsetTitle = p.label("歌词时间偏移", "Lyric timing offset")
        if let songID = model.lyricOffsetSongID, let offset = model.lyricOffset {
            let item = menu.addItem(withTitle: "\(offsetTitle) (\(p.offsetLabel(offset)))", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for action in LyricOffsetAction.allCases {
                let option = submenu.addItem(withTitle: action.title(p), action: #selector(adjustLyricOffset(_:)), keyEquivalent: "")
                option.target = self
                option.tag = action.rawValue
                option.representedObject = songID
                option.isEnabled = action != .reset || offset != 0
            }
            item.submenu = submenu
        } else {
            menu.addItem(withTitle: offsetTitle, action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: p.label("退出波点歌词", "Quit Bodian Lyrics"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func adjustLyricOffset(_ sender: NSMenuItem) {
        guard let songID = sender.representedObject as? String, songID == model.lyricOffsetSongID,
              let action = LyricOffsetAction(rawValue: sender.tag) else { return }
        model.adjustLyricOffset(action)
    }

    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = model.preferences.label("波点歌词设置", "Bodian Lyrics Settings")
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
