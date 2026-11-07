import SwiftUI
import BodianCore

struct NotchHangingShape: Shape {
    /// nil 表示按高度计算圆角。
    var bottomCornerRadius: CGFloat?
    /// 肩膀按哪个刘海高度算;nil = 没有肩膀。
    var notchHeight: CGFloat?
    func cornerMetrics(in rect: CGRect) -> (shoulder: CGFloat, radius: CGFloat) {
        let s = notchHeight.map { NotchOutline.shoulder(width: rect.width, height: rect.height, notchHeight: $0) } ?? 0
        let bodyWidth = rect.width - 2 * s
        let r: CGFloat
        if let fixed = bottomCornerRadius {
            r = min(fixed, bodyWidth / 2, rect.height / 2)
        } else {
            r = NotchOutline.bottomRadius(height: rect.height, bodyWidth: bodyWidth)
        }
        return (s, r)
    }

    func path(in rect: CGRect) -> Path {
        let (s, r) = cornerMetrics(in: rect)
        let left = rect.minX + s
        let right = rect.maxX - s
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if s > 0 {
            // 右肩:圆心在主体外侧,从顶边弯进右侧边 —— 内凹。
            path.addFlattenedArc(center: CGPoint(x: rect.maxX, y: rect.minY + s), radius: s,
                                 from: .degrees(-90), to: .degrees(-180))
        }
        path.addLine(to: CGPoint(x: right, y: rect.maxY - r))
        path.addFlattenedArc(center: CGPoint(x: right - r, y: rect.maxY - r), radius: r,
                             from: .degrees(0), to: .degrees(90))
        path.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        path.addFlattenedArc(center: CGPoint(x: left + r, y: rect.maxY - r), radius: r,
                             from: .degrees(90), to: .degrees(180))
        if s > 0 {
            path.addLine(to: CGPoint(x: left, y: rect.minY + s))
            path.addFlattenedArc(center: CGPoint(x: rect.minX, y: rect.minY + s), radius: s,
                                 from: .degrees(0), to: .degrees(-90))
        }
        path.closeSubpath()
        return path
    }
}

extension Path {
    /// 从 `start` 到 `end`(角度直接插值,走的是两者之间那一段)的圆弧,按 `ArcFlattening` 拆成折线;先从当前点连线到
    /// 弧的起点。别换回 `addArc` / `addCurve`:渲染器拆曲线拆得粗,弧线边缘有台阶。
    mutating func addFlattenedArc(center: CGPoint, radius: CGFloat, from start: Angle, to end: Angle) {
        let a0 = start.radians, a1 = end.radians
        let n = ArcFlattening.segments(radius: radius, sweep: CGFloat(a1 - a0))
        for k in 0...n {
            let a = a0 + (a1 - a0) * Double(k) / Double(n)
            let point = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            if k == 0, isEmpty { move(to: point) } else { addLine(to: point) }
        }
    }
}

struct NotchEarProgressShape: Shape {
    let card: NotchHangingShape
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var cardSize: CGSize
    let mirrored: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cardSize.width, cardSize.height) }
        set { cardSize = CGSize(width: newValue.first, height: newValue.second) }
    }

    static func geometry(size: CGSize, card: NotchHangingShape, notchWidth: CGFloat,
                         notchHeight: CGFloat) -> NotchEarProgressPath {
        let corner = card.cornerMetrics(in: CGRect(origin: .zero, size: size))
        return NotchEarProgressPath(width: size.width, height: size.height, notchWidth: notchWidth, notchHeight: notchHeight,
                                    shoulder: corner.shoulder, cardCornerRadius: corner.radius,
                                    inset: 0.75)
    }

    func path(in rect: CGRect) -> Path {
        let path = Self.geometry(size: cardSize, card: card, notchWidth: notchWidth, notchHeight: notchHeight)
        let r = path.cornerRadius
        var p = Path()
        p.move(to: CGPoint(x: path.startX, y: 0))
        if path.shoulderRadius > 0 {
            p.addFlattenedArc(center: CGPoint(x: 0, y: path.shoulderCenterY), radius: path.shoulderRadius,
                              from: .radians(-Double(path.shoulderSweep)), to: .zero)
        }
        p.addLine(to: CGPoint(x: path.x, y: path.bottomY - r))
        p.addFlattenedArc(center: CGPoint(x: path.x + r, y: path.bottomY - r), radius: r,
                          from: .degrees(180), to: .degrees(90))
        p.addLine(to: CGPoint(x: path.endX, y: path.bottomY))
        let left = rect.midX - cardSize.width / 2
        let flip = mirrored ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: cardSize.width, ty: 0) : .identity
        return p.applying(flip.concatenating(CGAffineTransform(translationX: left, y: rect.minY)))
    }
}
