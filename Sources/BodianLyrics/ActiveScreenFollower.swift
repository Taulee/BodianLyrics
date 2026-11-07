import AppKit
import BodianCore

@MainActor
final class ActiveScreenFollower {
    /// 同一个 App 的窗口拖到另一块屏上时系统不发通知,靠这一拍兜底;前台 App 换了的通知让大多数换屏不用等这一拍。
    static let pollInterval: TimeInterval = 1

    var onFollow: (NSScreen) -> Void = { _ in }
    var canMove: () -> Bool = { true }

    private var settle = ActiveScreenSettle()
    private var appObserver: NSObjectProtocol?
    private var timer: Timer?

    /// 要不要盯。开始盯的这一刻当场跟一次。每秒一次的兜底只在多屏时开:单屏时焦点屏不会变,每拍跨进程列一遍窗口
    /// (`focusedScreen`)是白做;屏幕数变了宿主在屏幕参数通知里再调一次。
    func update(wanted: Bool) {
        let wantsPoll = wanted && NSScreen.screens.count > 1
        guard wanted != (appObserver != nil) || wantsPoll != (timer != nil) else { return }
        stop()
        guard wanted else { return }
        settle.start()
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        if wantsPoll {
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            timer.tolerance = Self.pollInterval * 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        follow()
    }

    /// 当场跟一次焦点屏。前台 App 此刻没有在屏的普通窗口(只剩桌面)时不动。
    func follow() {
        guard let screen = Self.focusedScreen(), let id = ScreenIdentity.id(of: screen) else { return }
        settle.followed(id)
        onFollow(screen)
    }

    /// 焦点屏换了没有:换了先记下,稳定 `ActiveScreenSettle.delay` 再搬;不能搬的时候不动。
    private func check() {
        guard canMove(), let id = Self.focusedScreen().flatMap(ScreenIdentity.id(of:)) else { return }
        switch settle.observe(id, at: Date()) {
        case .none:
            break
        case .wait:
            DispatchQueue.main.asyncAfter(deadline: .now() + ActiveScreenSettle.delay) { [weak self] in
                self?.check()
            }
        case .follow:
            follow()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }
        settle.stop()
    }

    /// 按前台应用的首个可见窗口确定焦点屏幕。
    static func focusedScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        // 列表按从前到后排:前台 App 的第一扇看得见的普通窗口就是它最前面那扇。太小的多半是看不见的辅助窗口。
        for info in windows where (info[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (info[kCGWindowLayer as String] as? Int) == 0
            && ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0 {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.width >= 40, bounds.height >= 40 else { continue }
            let screens = NSScreen.screens
            return OverlayPlacement.screenIndex(ofWindowBounds: bounds, screens: screens.map(\.frame)).map { screens[$0] }
        }
        return nil
    }
}
