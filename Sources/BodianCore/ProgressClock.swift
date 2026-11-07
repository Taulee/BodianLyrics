import Foundation

// 进度外推:锚点(progressMs)不会每一拍都刷新,真实位置 = progressMs + 锚点年龄(ms) * rate,
// 不限龄,夹在 [0, durationMs]。
/// 从最近一次 MediaRemote 锚点外推当前播放位置。
public struct ProgressAnchor {
    public let durationMs: Int
    public let progressMs: Int
    public let rate: Double
    public let progressTs: Int?   // 播放锚点的 Unix 毫秒
    public init(durationMs: Int, progressMs: Int, rate: Double, progressTs: Int?) {
        self.durationMs = durationMs
        self.progressMs = progressMs
        self.rate = rate
        self.progressTs = progressTs
    }


    public func extrapolatedPositionMs(now: Date = Date()) -> Int {
        let ageMs: Double
        if let ts = progressTs {
            ageMs = now.timeIntervalSince1970 * 1000 - Double(ts)
        } else {
            ageMs = 0
        }
        var pos = Double(progressMs)
        if rate > 0, ageMs > 0 {
            pos += ageMs * rate
        }
        pos = max(0, min(Double(durationMs), pos))
        return Int(pos)
    }
}
