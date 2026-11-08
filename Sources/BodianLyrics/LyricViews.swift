import AppKit
import BodianCore
import SwiftUI

struct MenuText: Equatable {
    let text: String
    let words: [SyncedLyricWord]
    let width: CGFloat

    init(_ text: String, words: [SyncedLyricWord] = [], font: NSFont, characterLimit: Int = .max) {
        self.text = String(text.prefix(characterLimit))
        width = textWidth(self.text, font: font)

        var remaining = self.text.count
        var visibleWords: [SyncedLyricWord] = []
        for word in words where remaining > 0 {
            let prefix = word.text.prefix(remaining)
            visibleWords.append(SyncedLyricWord(text: String(prefix), startMs: word.startMs, durationMs: word.durationMs))
            remaining -= prefix.count
        }
        self.words = visibleWords.map(\.text).joined() == self.text ? visibleWords : []
    }
}

struct LyricText: View, Equatable {
    let content: MenuText
    let position: Int?
    let age: Double
    let font: NSFont
    let width: CGFloat
    let alignment: Alignment
    let fill: Color
    let unsung: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content && lhs.age == rhs.age && lhs.font == rhs.font
            && lhs.width == rhs.width && lhs.alignment == rhs.alignment && lhs.fill == rhs.fill
            && lhs.unsung == rhs.unsung
            && (lhs.content.words.isEmpty || lhs.position == rhs.position)
    }

    private var ink: Text {
        guard let position, !content.words.isEmpty else { return Text(verbatim: content.text).foregroundColor(fill) }
        let palette = WordKaraokeGradient.palette(fg: fill, unsungColor: unsung)
        return content.words.reduce(Text("")) { result, word in
            let fraction = KaraokeFill.fillFraction(for: word, atMs: position)
            let edge = KaraokeFill.wordEdgeSoftenBand
            return result + Text(verbatim: word.text).foregroundStyle(palette.style(left: fraction - edge, right: fraction + edge))
        }
    }

    var body: some View {
        let cycle = reduceMotion ? nil : MarqueeMath.cycle(contentWidth: content.width, containerWidth: width)
        let offset = cycle.map { cycle in
            let elapsed = (max(0, age) + cycle.firstCycleTimeOffset).truncatingRemainder(dividingBy: cycle.period)
            return min(cycle.distance, max(0, elapsed - cycle.startHold) * MarqueeMath.pointsPerSecond)
        } ?? 0
        let fade = cycle == nil ? 0 : MarqueeMath.trailingFadeWidth(configured: 12, contentWidth: content.width,
                                                                   containerWidth: width, offset: offset)
        ink.font(Font(font)).lineLimit(1)
            .fixedSize(horizontal: cycle != nil, vertical: false)
            .offset(x: -offset)
            .frame(width: width, alignment: cycle == nil ? alignment : .leading)
            .clipped()
            .mask {
                if fade > 0 {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: fade)
                    }
                } else {
                    Rectangle()
                }
            }
            .accessibilityLabel(content.text)
    }
}
