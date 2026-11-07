import Foundation

/// 词条带原文及相对整首歌的绝对毫秒时间。
public struct SyncedLyricWord: Equatable, Decodable, Sendable {
    public let text: String
    // 真实起止时间戳(绝对播放位置,毫秒)。填色进度不在这里预烤成一个数字,由 View 层用 TimelineView 按渲染帧频、从连续
    // 时钟直接现算 fillFraction。别改成"这里预算 fillFraction、定时 tick 推进 @Published、View 端 .animation(.linear) 补间":
    // 补间时长比 tick 间隔长时总在上一段没放完就被重新触发,SwiftUI 对 .linear 这类不可合并的曲线动画是把新旧两段位移矢量
    // 相加而不是从当前值接续,逐字流转会卡顿。
    public let startMs: Int
    public let durationMs: Int

    public init(text: String, startMs: Int, durationMs: Int) {
        self.text = text
        self.startMs = startMs
        self.durationMs = durationMs
    }
}
