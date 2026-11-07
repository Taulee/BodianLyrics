import AppKit
import Combine
import BodianCore

@MainActor
final class FullScreenSpaceMonitor: ObservableObject {
    static let shared = FullScreenSpaceMonitor()

    /// 当前 Space 为全屏的屏幕标识(大写 UUID 串,或 `FullScreenSpaces.sharedSpacesIdentifier`)。
    @Published private(set) var fullScreenDisplays: Set<String> = []

    private static let settleDelay: TimeInterval = 0.6
    private var observers: [NSObjectProtocol] = []
    private var settleWork: DispatchWorkItem?

    private init() {
        refresh()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNowAndAfterSettle() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNowAndAfterSettle() }
        })
    }

    /// 这块屏幕此刻是否被全屏 App 占着。
    func covers(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return FullScreenSpaces.covers(screenID: ScreenIdentity.id(of: screen),
                                       isMainScreen: screen == NSScreen.screens.first,
                                       fullScreenDisplays: fullScreenDisplays)
    }

    /// 切换通知可能先于 Space 表更新，因此稍后再读一次。
    private func refreshNowAndAfterSettle() {
        refresh()
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func refresh() {
        let raw = Self.spaceFunctions.flatMap { mainConnection, copySpaces in
            copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        } ?? []
        let next = FullScreenSpaces.fullScreenDisplays(in: raw)
        if next != fullScreenDisplays { fullScreenDisplays = next }
    }
}

extension FullScreenSpaceMonitor {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let spaceFunctions: (MainConnectionID, CopyManagedDisplaySpaces)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let main = dlsym(handle, "CGSMainConnectionID"),
              let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        return (unsafeBitCast(main, to: MainConnectionID.self), unsafeBitCast(copy, to: CopyManagedDisplaySpaces.self))
    }()
}
