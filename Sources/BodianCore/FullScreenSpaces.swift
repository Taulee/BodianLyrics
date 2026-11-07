/// 读出当前处于全屏 Space 的显示器标识。
public enum FullScreenSpaces {
    /// 系统设置里「显示器具有单独的空间」关掉时只有一项,标识是这个字面量,对应主屏。
    public static let sharedSpacesIdentifier = "Main"

    /// 当前 Space 是全屏的屏幕标识,统一转成大写(屏幕 UUID 串两边大小写写法不保证一致)。
    public static func fullScreenDisplays(in displays: [[String: Any]]) -> Set<String> {
        var result: Set<String> = []
        for display in displays {
            guard let id = display["Display Identifier"] as? String,
                  let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let active = spaces.first(where: { ($0["ManagedSpaceID"] as? Int) == current })
            else { continue }
            if active["TileLayoutManager"] != nil { result.insert(id.uppercased()) }
        }
        return result
    }

    /// 这块屏幕此刻是否被全屏 App 占着。`screenID` 是 `CGDisplayCreateUUIDFromDisplayID` 的字符串形式。
    public static func covers(screenID: String?, isMainScreen: Bool, fullScreenDisplays: Set<String>) -> Bool {
        if isMainScreen, fullScreenDisplays.contains(sharedSpacesIdentifier.uppercased()) { return true }
        guard let screenID else { return false }
        return fullScreenDisplays.contains(screenID.uppercased())
    }
}
