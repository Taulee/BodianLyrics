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
        Int(max(0, min(Double(durationMs), positionMs(at: now))))
    }

    fileprivate func positionMs(at now: Date) -> Double {
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
        return pos
    }
}

/// 保持连续播放的显示位置连续，同时让拖动进度条后的明显跳变立即生效。
public struct LyricPlaybackClock {
    public static let jitterToleranceMs = 1_200

    private let anchor: ProgressAnchor
    private let updatedAt: Date
    private let correction: Double
    private let correctionDuration: Double

    public init(anchor: ProgressAnchor, previous: Self?, now: Date) {
        self.anchor = anchor
        updatedAt = now
        let delta = previous.map { $0.positionMs(at: now) - anchor.positionMs(at: now) } ?? 0
        // 波点的整秒进度与采样时间可相差近一秒。换歌、暂停及更大的进度变化直接对齐。
        if anchor.rate > 0, anchor.progressTs != nil, let previous,
           previous.anchor.rate == anchor.rate, previous.anchor.progressTs != nil,
           abs(delta) <= Double(Self.jitterToleranceMs) {
            correction = delta
            correctionDuration = max(3, abs(delta) / (500 * anchor.rate))
        } else {
            correction = 0
            correctionDuration = 3
        }
    }

    public func position(at date: Date) -> Int {
        Int(max(0, min(Double(anchor.durationMs), positionMs(at: date))))
    }

    private func positionMs(at date: Date) -> Double {
        let progress = min(1, max(0, date.timeIntervalSince(updatedAt) / correctionDuration))
        return anchor.positionMs(at: date) + correction * (1 - progress)
    }
}
