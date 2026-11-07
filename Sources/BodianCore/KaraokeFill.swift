import Foundation

/// 依据播放位置计算逐字高亮进度，并把行尾高亮限制在下一句之前。
public enum KaraokeFill {
    public static let minWordDurationMs = 80

    /// 一行的最后一个字必须在换行前多久填满。30Hz 下 140ms ≈ 4 帧 —— 足够真的看见
    /// "这一行填满了"这个状态,又不至于让填色明显赶在音频前面。
    public static let lineTailLeadMs = 140

    /// 无论怎么压,最后一个字至少要留这么久可扫。否则短字会变成"啪"地一下跳满,
    /// 比没填完更难看。
    public static let minTailFillMs = 120

    /// 让一行的**最后一个字**在换行之前就填满。
    ///
    /// 为什么需要:"填满"的时刻是 `字.startMs + 字.durationMs`,而"换行"的时刻是**下一行的
    /// timeMs** —— 这是歌词文件里两个各自独立的数字,谁也不保证前者更早。拿本机
    /// 整个歌词库实测(667 首 / 37610 行):
    ///
    ///   * **25.9%** 的行两者**正好相等** —— 填满和换行同一毫秒发生,于是永远看不到"填满"
    ///     那一帧(换行前最后一帧只到 ~97%);
    ///   * **3.0%** 真的越过下一行开始(中位 295ms,95% 在 300ms 内,像是各家歌词源给末字
    ///     统一加的一小截尾巴);
    ///   * 另有 **12.2%** 余量不足 120ms(30Hz 下不到 4 帧,看着一样像没填完)。
    ///
    /// 合计约四成的行都会表现成现象是"最后一点不走完就下一句"。有些歌是 100%(实测
    /// Dijon/Daniel Caesar 的几张专辑整张都是)。
    ///
    /// 只**缩**最后一个字的终点,不动 startMs、不动换行时刻、不碰其它字 —— 下一句一秒
    /// 都不会迟到。真正越过太多的行(压完不足 minTailFillMs)按下限兜住:那种情况下"填满"
    /// 和"不跳变"没法同时满足,宁可不跳变。
    public static func tailClamped(_ words: [SyncedLyricWord], nextLineStartMs: Int?) -> [SyncedLyricWord] {
        // 没有下一行(整首最后一句)= 没有换行这回事,原样返回。
        guard let nextLineStartMs, let last = words.last else { return words }
        let rawDuration = max(last.durationMs, minWordDurationMs)
        let room = nextLineStartMs - lineTailLeadMs - last.startMs
        let clamped = max(min(rawDuration, room), minTailFillMs)
        guard clamped < rawDuration else { return words }
        var out = words
        out[out.count - 1] = SyncedLyricWord(text: last.text, startMs: last.startMs,
                                             durationMs: clamped)
        return out
    }

    /// 过渡带半宽(fraction 单位)——真正需要柔化的只是"刚好唱到/刚好唱完"这个边界附近
    /// 一小段,不是整个 [0,1] 区间。
    public static let wordEdgeSoftenBand = 0.08

    /// 故意不夹到 [0,1]——如果夹住,"还没轮到、离真正唱到还有好几个字/好几句"的词会
    /// 全都被夹成跟"刚好唱到这个词最前一刻"相同的 0,调用方(stops)里的过渡带因此会
    /// 在每一个尚未唱到的词开头误算出一小截"已经唱过"的高亮。真正需要的裁剪在 stops
    /// 里按"过渡带跟 [0,1] 是否有交集"分情况处理。
    public static func fillFraction(for w: SyncedLyricWord, atMs ms: Int) -> Double {
        fillFraction(startMs: w.startMs, durationMs: w.durationMs, atMs: ms)
    }

    private static func fillFraction(startMs: Int, durationMs: Int, atMs ms: Int) -> Double {
        let effectiveDuration = max(durationMs, minWordDurationMs)
        return Double(ms - startMs) / Double(effectiveDuration)
    }

    /// 渐变上的一个分段点。`intensity` 是"唱过的程度":1 = 前景色全强度,0 = 未唱到的暗色。
    /// 具体映射到什么颜色由 UI 层决定,这里不掺和。
    public struct Stop: Equatable, Sendable {
        public let location: Double
        public let intensity: Double

        public init(location: Double, intensity: Double) {
            self.location = location
            self.intensity = intensity
        }
    }

    /// 把过渡带 `[left, right]`(以这个字真实的、未夹过的进度为中心)转成渐变分段。
    ///
    /// 过渡带可能整段落在 [0,1] 之外:离真正唱到还很远的字(right<=0)、早就唱完很久的字
    /// (left>=1),两种都不需要渐变,直接给一整片纯色。只有过渡带真跟 [0,1] 有交集时,才在
    /// 被夹住的那一端**现算**准确的混合值(而不是硬编码成"已唱"或"未唱")——否则同一个
    /// 位置会出现两个不同颜色的 stop,渲染时其中一个被另一个抢占,边界上就会闪。
    /// 两个纯色快路径的常量分段:一行里任一时刻只有 ~1 个词的过渡带
    /// 真跟 [0,1] 相交,其余词全走这两条 —— 原来每次调用都重新分配一个内容恒定的 2 元素
    /// 数组,三个 30Hz 展示面同开时每秒上千次纯浪费。静态常量还让调用方能按引用复用同一
    /// 份实例(见 WordKaraokeGradient 的纯色渐变缓存)。
    public static let allUnsungStops: [Stop] = [
        Stop(location: 0, intensity: 0), Stop(location: 1, intensity: 0),
    ]
    public static let allSungStops: [Stop] = [
        Stop(location: 0, intensity: 1), Stop(location: 1, intensity: 1),
    ]

    public static func stops(left: Double, right: Double) -> [Stop] {
        if right <= 0 { return allUnsungStops }
        if left >= 1 { return allSungStops }
        // 过渡带内某个位置的强度:从 left 处的 1 线性降到 right 处的 0。
        func intensity(at x: Double) -> Double {
            let t = min(1, max(0, (x - left) / (right - left)))
            return 1 - t
        }
        var result: [Stop] = []
        result.reserveCapacity(4)
        if left > 0 {
            result.append(Stop(location: 0, intensity: 1))
            result.append(Stop(location: left, intensity: 1))
        } else {
            result.append(Stop(location: 0, intensity: intensity(at: 0)))
        }
        if right < 1 {
            result.append(Stop(location: right, intensity: 0))
            result.append(Stop(location: 1, intensity: 0))
        } else {
            result.append(Stop(location: 1, intensity: intensity(at: 1)))
        }
        return result
    }
}
