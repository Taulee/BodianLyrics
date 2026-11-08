import AppKit
import SwiftUI
import BodianCore

/// 将高亮计算得到的色阶转换成 SwiftUI 渐变。
enum WordKaraokeGradient {
    /// 显示面以 30 Hz 更新逐字高亮。
    static let refreshInterval: Double = 1.0 / 30.0

    static let dimOpacity: Double = 0.35

    /// unsungColor 传 nil(默认)就是上面这条"同一个 fg 调暗"的老路,零行为变化。传了
    /// 具体颜色("已唱/未唱"分开配色),未唱端
    /// 就换成这个独立颜色,在它和 fg 之间按每个 stop 的 intensity 做真正的颜色插值
    /// (`mix`)——不再是同一色的透明度插值,两种颜色可以完全不同的色相。
    ///
    /// 只有**真正处于过渡带**的那个词会走这条路(见 Palette.style:纯"已唱"/"未唱"两端
    /// 直接命中缓存的纯色实例,根本不调 gradient()),一行里同一时刻最多一个词在过渡带、
    /// 每次最多 4 个 stop,30~60Hz 下这几次 NSColor 转换可以忽略,不影响之前审计过的
    /// 性能预算。
    static func gradient(fg: Color, unsungColor: Color? = nil, dimOpacity: Double = WordKaraokeGradient.dimOpacity,
                         left: Double, right: Double) -> LinearGradient {
        let stops = KaraokeFill.stops(left: left, right: right).map { stop -> Gradient.Stop in
            let color: Color
            if let unsungColor {
                color = mix(unsungColor, fg, t: stop.intensity)
            } else {
                color = fg.opacity(dimOpacity + stop.intensity * (1 - dimOpacity))
            }
            return Gradient.Stop(color: color, location: stop.location)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// sRGB 分量线性插值,t=0 是 a、t=1 是 b。只用来在"未唱色"和"已唱色"之间过渡——
    /// 不追求感知均匀空间那一套,过渡带只有 wordEdgeSoftenBand(0.08)宽,肉眼分不出差别。
    private static func mix(_ a: Color, _ b: Color, t: Double) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(t) }
        return Color(nsColor: NSColor(
            srgbRed: lerp(ca.redComponent, cb.redComponent),
            green: lerp(ca.greenComponent, cb.greenComponent),
            blue: lerp(ca.blueComponent, cb.blueComponent),
            alpha: lerp(ca.alphaComponent, cb.alphaComponent)
        ))
    }

    struct Palette {
        let fg: Color
        /// nil = 未唱端是 fg 调到 `dimOpacity`;非 nil = 未唱端换成这个独立颜色。
        let unsungColor: Color?
        let dimOpacity: Double
        let dimStyle: AnyShapeStyle
        let fullStyle: AnyShapeStyle

        init(fg: Color, unsungColor: Color? = nil, dimOpacity: Double = WordKaraokeGradient.dimOpacity) {
            self.fg = fg
            self.unsungColor = unsungColor
            self.dimOpacity = dimOpacity
            let dim = unsungColor ?? fg.opacity(dimOpacity)
            dimStyle = AnyShapeStyle(LinearGradient(
                colors: [dim, dim], startPoint: .leading, endPoint: .trailing))
            fullStyle = AnyShapeStyle(LinearGradient(
                colors: [fg, fg], startPoint: .leading, endPoint: .trailing))
        }

        /// 纯色两端复用缓存实例,过渡带现算 —— 判据与 KaraokeFill.stops 的快路径完全一致。
        func style(left: Double, right: Double) -> AnyShapeStyle {
            if right <= 0 { return dimStyle }
            if left >= 1 { return fullStyle }
            return AnyShapeStyle(WordKaraokeGradient.gradient(fg: fg, unsungColor: unsungColor, dimOpacity: dimOpacity,
                                                              left: left, right: right))
        }
    }

    // 复用同色的纯已唱与纯未唱渐变，只有活跃词需生成过渡渐变。
    @MainActor private static var paletteCache: [Palette] = []

    @MainActor static func palette(fg: Color, unsungColor: Color? = nil,
                                   dimOpacity: Double = WordKaraokeGradient.dimOpacity) -> Palette {
        if let hit = paletteCache.first(where: {
            $0.fg == fg && $0.unsungColor == unsungColor && $0.dimOpacity == dimOpacity
        }) { return hit }
        let p = Palette(fg: fg, unsungColor: unsungColor, dimOpacity: dimOpacity)
        paletteCache.append(p)
        // 调色时会产生新条目，限制缓存容量。
        if paletteCache.count > 8 { paletteCache.removeFirst() }
        return p
    }
}
