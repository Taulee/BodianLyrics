import CoreGraphics

/// 计算灵动岛外形的肩部、底角和圆角范围。
public enum NotchOutline {
    public static let bottomRadiusPerHeight: CGFloat = 0.25
    public static let maxBottomRadius: CGFloat = 20
    public static let shoulderPerNotchHeight: CGFloat = 0.125

    /// 肩膀的标称半径。`notchHeight` 是顶行高度(真刘海屏 = 刘海本身,无刘海屏 = 菜单栏高)。
    public static func shoulderRadius(notchHeight: CGFloat) -> CGFloat {
        max(0, notchHeight * shoulderPerNotchHeight)
    }

    /// 某个矩形实际用的肩膀半径:矩形太窄 / 太矮时收小(出场动画起始那一帧只有一条缝)。
    public static func shoulder(width: CGFloat, height: CGFloat, notchHeight: CGFloat) -> CGFloat {
        max(0, min(shoulderRadius(notchHeight: notchHeight), width / 4, height / 2))
    }

    /// 底部圆角半径。`bodyWidth` 是两侧收完肩膀之后的主体宽度。
    public static func bottomRadius(height: CGFloat, bodyWidth: CGFloat) -> CGFloat {
        max(0, min(maxBottomRadius, height * bottomRadiusPerHeight, bodyWidth / 2, height / 2))
    }
}
