import AppKit
import BodianCore
import SwiftUI

struct SurfaceView: View {
    @ObservedObject var model: PlaybackModel
    let surface: Surface
    var preview = false
    var iconOnly = false
    var notchWidth: CGFloat = 94
    var topHeight: CGFloat = 28
    var onHover: (Bool) -> Void = { _ in }

    @State private var previewStart = Date()

    var body: some View {
        let p = model.preferences
        let font = model.font(for: surface)
        let previewLayout = preview ? Self.previewLayout(p, font: font, width: model.width(for: surface), surface: surface) : nil
        let track = preview ? Self.previewTrack(p) : model.playback.track
        let layout = previewLayout ?? model.layouts[surface] ?? LyricLayout([], width: 1, font: font, secondary: .off, options: .off)
        let offset = p.offsets[model.playback.id, default: 0]
        TimelineView(.animation(minimumInterval: WordKaraokeGradient.refreshInterval,
                                paused: !preview && (track?.playing != true || iconOnly))) { context in
            let elapsed = context.date.timeIntervalSince(previewStart)
            let position = preview ? Int(max(0, elapsed) * 1000) % 10_000
                : track?.anchor.extrapolatedPositionMs(now: context.date) ?? 0
            let frame = SurfaceFrame(track: track, layout: layout, position: position, lyricPosition: position + (preview ? 0 : offset),
                                     changedAgo: preview ? max(0, elapsed) : context.date.timeIntervalSince(model.trackChangedAt))
            if surface == .menu {
                MenuLyricsView(preferences: p, frame: frame, font: font, iconOnly: iconOnly, preview: preview)
            } else {
                IslandView(preferences: p, frame: frame, font: font, artwork: model.artwork, coverTint: model.coverTint,
                           notchWidth: notchWidth, topHeight: topHeight, expanded: surface == .expanded,
                           collapsed: surface == .island && p.islandCollapseWhenPaused && track?.playing != true,
                           onHover: onHover, onOffset: { change in
                               let id = model.playback.id
                               if !preview && !id.isEmpty { model.preferences.offsets[id, default: 0] += change }
                           })
            }
        }
    }

    private static func previewTrack(_ preferences: Preferences) -> Track {
        Track(title: preferences.label("歌词预览", "Lyrics Preview"), artist: "Bodian Lyrics", album: "Preview",
              duration: 10, anchorElapsedTime: 0, timestamp: 0, playbackRate: 1, playing: true)
    }

    private static func previewLayout(_ preferences: Preferences, font: NSFont, width: CGFloat, surface: Surface) -> LyricLayout {
        let texts = [
            ("Along the shore the lights go by", "沿岸的灯火渐渐远去", 0, 2700),
            ("Stay", "留下", 2900, 3500),
            ("Where the evening meets the sea", "在暮色与海相遇的地方", 3600, 6500),
            ("We can watch the moon rise", "我们可以一起看月亮升起", 6800, 9700)
        ]
        let lines = texts.map { text, translation, start, end in
            let tokens = text.split(separator: " ")
            let duration = (end - start) / tokens.count
            let words = tokens.enumerated().map { i, token in
                SyncedLyricWord(text: i + 1 == tokens.count ? String(token) : String(token) + " ",
                               startMs: start + i * duration, durationMs: duration)
            }
            return LyricLine(startMs: start, endMs: end, text: text, words: words, translation: translation)
        }
        return LyricLayout(lines, width: width, font: font,
                           secondary: surface == .menu ? preferences.menuSecondary : preferences.islandSecondary,
                           options: LineBreakOptions(splitsLongLines: preferences.splitLongLines,
                                                     mergesShortLines: preferences.mergeShortLines))
    }
}
