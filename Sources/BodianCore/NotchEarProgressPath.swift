import CoreGraphics
import Foundation

public struct NotchEarProgressPath: Equatable, Sendable {
    /// 肩膀圆心的 y(圆心在卡片左沿 x = 0 上),也是肩膀弧和竖段的交点高度。没有肩膀时为 0。
    public var shoulderCenterY: CGFloat
    /// 肩膀那段弧的半径(肩膀半径加 `inset`,同心);没有肩膀时为 0。
    public var shoulderRadius: CGFloat
    /// 起笔点(屏幕上沿,y = 0)的 x。
    public var startX: CGFloat
    /// 竖段的 x。
    public var x: CGFloat
    /// 底边那一段的 y。
    public var bottomY: CGFloat
    /// 底角那段圆弧的半径(卡片底角半径减去 `inset`,同心)。
    public var cornerRadius: CGFloat
    /// 终点的 x。
    public var endX: CGFloat

    /// 底边露出刘海下沿多少之后终点走到正中。
    public static let bottomRevealSpan: CGFloat = 12

    /// - Parameters:
    ///   - shoulder / cardCornerRadius: 卡片外形此刻的肩膀和底角半径(App 侧 `NotchHangingShape.cornerMetrics`)。
    ///   - notchHeight: 顶行高度(真刘海屏 = 刘海高)。
    public init(width: CGFloat, height: CGFloat, notchWidth: CGFloat, notchHeight: CGFloat,
                shoulder: CGFloat, cardCornerRadius: CGFloat, inset: CGFloat) {
        x = shoulder + inset
        shoulderCenterY = max(0, shoulder)
        shoulderRadius = shoulder > 0 ? shoulder + inset : 0
        startX = shoulder > 0 ? (shoulderRadius * shoulderRadius - shoulder * shoulder).squareRoot() : x
        bottomY = max(0, height - inset)
        cornerRadius = max(0, min(cardCornerRadius - inset, bottomY - shoulderCenterY))
        let center = width / 2
        let revealed = notchWidth > 0 ? min(1, max(0, (height - notchHeight) / Self.bottomRevealSpan)) : 1
        endX = max(x + cornerRadius, center - notchWidth / 2 * (1 - revealed))
    }

    /// 肩膀那段弧扫过的角度(弧度):从起笔点转到弧和竖段的交点。
    public var shoulderSweep: CGFloat {
        shoulderRadius > 0 ? asin(min(1, shoulderCenterY / shoulderRadius)) : 0
    }
}
