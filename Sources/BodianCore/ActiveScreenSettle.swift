import Foundation

public struct ActiveScreenSettle: Sendable {
    /// 焦点屏换了之后等多久才搬:快速切几个 App 时不来回闪。
    public static let delay: TimeInterval = 0.5

    public enum Decision: Equatable, Sendable {
        /// 什么都不做。
        case none
        /// 刚换到一块新屏:过 `delay` 再看一次。
        case wait
        /// 稳定够久了:跟过去(调用方再调 `followed(_:)`)。
        case follow
    }

    /// 上一次跟过去的焦点屏;nil = 还没跟过(刚打开开关 / 刚启动,下一次无论在哪块屏都跟)。
    public private(set) var followedID: String?
    /// 这会儿在不在盯。没在盯时 `observe` 一律不动:关掉跟随、宿主藏起来之前排下的复查到点了也不搬。
    public private(set) var isTracking = false
    private var pending: (id: String, since: Date)?

    public init() {}

    /// 开始盯:之前等着的那块作废。
    public mutating func start() {
        isTracking = true
        pending = nil
    }

    /// 停止盯。
    public mutating func stop() {
        isTracking = false
    }

    /// 看到焦点屏是 `id`(时刻 `now`)。
    public mutating func observe(_ id: String, at now: Date) -> Decision {
        guard isTracking else { return .none }
        guard id != followedID else {
            pending = nil
            return .none
        }
        guard let pending, pending.id == id else {
            self.pending = (id, now)
            return .wait
        }
        return now.timeIntervalSince(pending.since) >= Self.delay ? .follow : .none
    }

    /// 已经跟到 `id` 了。
    public mutating func followed(_ id: String) {
        followedID = id
        pending = nil
    }
}
