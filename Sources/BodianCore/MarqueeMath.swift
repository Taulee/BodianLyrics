import CoreGraphics
import Foundation

/// 计算长文本滚动的距离、停顿和渐隐宽度。
public enum MarqueeMath {
    /// 内容比容器宽出多少(负数 = 装得下)。
    public static func overflow(contentWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        contentWidth - containerWidth
    }

    /// 值得滚的死区。差这么一点点滚起来只是抖一下,不如不动;留给测量误差。
    public static let deadZone: CGFloat = 4

    public static func isOverflowing(contentWidth: CGFloat, containerWidth: CGFloat) -> Bool {
        containerWidth > 0
            && overflow(contentWidth: contentWidth, containerWidth: containerWidth) > deadZone
    }

    /// 右端渐隐带该有多宽。
    ///
    /// 文字溢出且停在起点时，用渐隐提示后面还有内容。滚到末端时保留最后一个字的完整显示。
    ///
    /// 返回**宽度**而不是 gradient 的 stop 位置,是为了让它可动画:`LinearGradient` 的
    /// stops 不是 Animatable,改 stop 会突变;把渐隐带做成一个 `.frame(width:)` 的子视图,
    /// 宽度变化就自然跟着 `withAnimation` 平滑收缩(跑马灯一起步渐隐带随之收掉)。
    public static func trailingFadeWidth(configured: CGFloat,
                                         contentWidth: CGFloat,
                                         containerWidth: CGFloat,
                                         offset: CGFloat) -> CGFloat {
        guard configured > 0,
              offset == 0,
              isOverflowing(contentWidth: contentWidth, containerWidth: containerWidth) else { return 0 }
        // 窄容器里至少留一半宽度完整显示文字。
        return min(configured, containerWidth / 2)
    }
}

extension MarqueeMath {
    public static let pointsPerSecond: Double = 24
    /// 停在开头、停在末尾的单位停顿(秒)。
    public static let holdDuration: Double = 1.1

    /// 装不下(超过死区)时的循环周期;装得下返回 nil。
    public static func cycle(contentWidth: CGFloat, containerWidth: CGFloat,
                             pointsPerSecond: Double = MarqueeMath.pointsPerSecond,
                             hold: Double = MarqueeMath.holdDuration) -> MarqueeCycle? {
        guard pointsPerSecond > 0,
              isOverflowing(contentWidth: contentWidth, containerWidth: containerWidth) else { return nil }
        let distance = overflow(contentWidth: contentWidth, containerWidth: containerWidth)
        return MarqueeCycle(distance: distance, travel: Double(distance) / pointsPerSecond, hold: hold)
    }
}

public struct MarqueeCycle: Equatable {
    /// 要滚的距离(点),> 0。
    public let distance: CGFloat
    /// 滚一遍的秒数。
    public let travel: Double
    /// 单位停顿(秒)。
    public let hold: Double

    public init(distance: CGFloat, travel: Double, hold: Double) {
        self.distance = distance
        self.travel = travel
        self.hold = hold
    }

    /// 每轮开头停多久(首轮见 `firstCycleTimeOffset`)。
    public var startHold: Double { 2 * hold }
    /// 一个周期的秒数。
    public var period: Double { startHold + travel + hold }
    /// 首轮从周期的这一刻起播。
    public var firstCycleTimeOffset: Double { hold }
}
