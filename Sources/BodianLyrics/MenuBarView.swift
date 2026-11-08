import AppKit
import BodianCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: PlaybackModel
    var preview = false
    var onWidthChange: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewStart = Date()

    private struct LineID: Equatable, Hashable {
        let songID: String
        let index: Int
    }

    var body: some View {
        let p = model.preferences
        let font = p.menuFont
        let track = model.playback.track
        let layout = preview ? Self.previewLayout(p) : model.layout
        let showsTrack = preview || track != nil
        let songText = track.flatMap { track in
            layout.lines.isEmpty
                ? MenuText([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " — "), font: font)
                : nil
        }
        let desired = songText?.width ?? layout.contentWidth
        let width = p.menuFixedWidth ? p.menuWidth : min(p.menuWidth, desired)
        let position = showsTrack ? p.menuPosition ?? MenuPosition() : MenuPosition()
        let padding = 2 * MenuPosition.horizontalLimit + 6
        let statusWidth = showsTrack ? max(24, ceil(width) + CGFloat(padding)) : 28

        Group {
            if !showsTrack {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityHidden(true)
            } else if let songText {
                TimelineView(.animation(minimumInterval: WordKaraokeGradient.refreshInterval,
                                        paused: reduceMotion || !MarqueeMath.isOverflowing(
                                            contentWidth: songText.width, containerWidth: width))) { context in
                    LyricText(content: songText, position: 0, age: context.date.timeIntervalSince(model.trackChangedAt),
                              font: font, width: width, alignment: p.menuAlignment.alignment,
                              fill: .primary, unsung: nil)
                        .equatable()
                }
            } else {
                lyricTimeline(layout: layout, track: track, font: font, width: width)
            }
        }
        .offset(x: CGFloat(position.x), y: CGFloat(position.y))
        .frame(width: statusWidth, height: NSStatusBar.system.thickness)
        .clipped()
        .onChange(of: statusWidth, initial: true) { _, width in onWidthChange(width) }
    }

    private func lyricTimeline(layout: LyricLayout, track: Track?, font: NSFont, width: CGFloat) -> some View {
        let p = model.preferences
        let songID = preview ? "" : model.playback.id
        let offset = preview ? 0 : model.lyricOffset ?? 0
        let clock = model.lyricClock
        let unsung = hexColor(p.menuTextColor)
        let fill = hexColor(p.menuFillColor) ?? unsung ?? .primary
        let centered = p.menuAlignment == .center
        let insertion: AnyTransition = centered ? .offset(x: 0, y: 14) : .offset(x: 14, y: 0)
        let removal: AnyTransition = centered ? .move(edge: .top).combined(with: .opacity) : .identity
        let transition: AnyTransition = reduceMotion ? .identity
            : .asymmetric(insertion: insertion.combined(with: .opacity), removal: removal)
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.32)

        return TimelineView(.animation(minimumInterval: WordKaraokeGradient.refreshInterval,
                                       paused: !preview && track?.playing != true)) { context in
            let position = preview ? Int(max(0, context.date.timeIntervalSince(previewStart)) * 1000) % 10_000
                : (clock?.position(at: .now) ?? 0) + offset
            let index = layout.activeIndex(at: position)
            let lineID = index.map { LineID(songID: songID, index: $0) }
            ZStack {
                if let lineID {
                    let line = layout.lines[lineID.index]
                    let scrolls = !reduceMotion && MarqueeMath.isOverflowing(contentWidth: line.text.width, containerWidth: width)
                    LyricText(content: line.text, position: p.menuKaraoke ? position : nil,
                              age: scrolls ? Double(position - line.startMs) / 1000 : 0,
                              font: font, width: width, alignment: p.menuAlignment.alignment,
                              fill: fill, unsung: unsung)
                        .equatable()
                        .frame(height: NSStatusBar.system.thickness)
                        .id(lineID)
                        .transition(transition)
                }
            }
            .frame(width: width, height: NSStatusBar.system.thickness)
            .clipped()
            .animation(animation, value: lineID)
        }
    }

    private static func previewLayout(_ preferences: Preferences) -> LyricLayout {
        let samples = [
            ("Along the shore the lights go by", 0, 2700),
            ("Stay", 2900, 3500),
            ("Where the evening meets the sea", 3600, 6500),
            ("We can watch the moon rise", 6800, 9700)
        ]
        let lines = samples.map { text, start, end in
            let tokens = text.split(separator: " ")
            let duration = (end - start) / tokens.count
            let words = tokens.enumerated().map { i, token in
                SyncedLyricWord(text: i + 1 == tokens.count ? String(token) : String(token) + " ",
                               startMs: start + i * duration, durationMs: duration)
            }
            return LyricLine(startMs: start, endMs: end, text: text, words: words)
        }
        return LyricLayout(lines, preferences: preferences)
    }
}
