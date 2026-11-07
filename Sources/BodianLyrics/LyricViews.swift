import AppKit
import BodianCore
import SwiftUI

struct Waveform: View {
    let size: CGFloat
    let animates: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size, weight: .medium))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: animates && !reduceMotion)
            .frame(width: size + 8)
            .accessibilityHidden(true)
    }
}

struct SurfaceFrame {
    let track: Track?
    let layout: LyricLayout
    let position: Int
    let lyricPosition: Int
    let changedAgo: TimeInterval

    var index: Int? { layout.activeIndex(at: lyricPosition) }
    var line: LyricLine? { index.map { layout.lines[$0] } }
    var next: String? {
        let next = (index ?? -1) + 1
        return layout.lines.indices.contains(next) && lyricPosition < layout.lines[next].startMs
            ? layout.lines[next].text : nil
    }
    var progress: Double {
        guard let track, track.duration > 0 else { return 0 }
        return Double(position) / (track.duration * 1000)
    }
}

struct LyricText: View {
    let text: String
    let words: [SyncedLyricWord]
    let position: Int
    let age: Double
    let font: NSFont
    let width: CGFloat
    let alignment: Alignment
    let fill: Color
    let unsung: Color?
    let rainbow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Text {
        guard !words.isEmpty else { return Text(verbatim: text).foregroundColor(fill) }
        let palette = WordKaraokeGradient.palette(fg: fill, unsungColor: unsung)
        return words.reduce(Text("")) { result, word in
            let fraction = KaraokeFill.fillFraction(for: word, atMs: position)
            let edge = KaraokeFill.wordEdgeSoftenBand
            return result + Text(verbatim: word.text).foregroundStyle(palette.style(left: fraction - edge, right: fraction + edge))
        }
    }

    var body: some View {
        let fullWidth = textWidth(text, font: font)
        let cycle = reduceMotion ? nil : MarqueeMath.cycle(contentWidth: fullWidth, containerWidth: width)
        let offset = cycle.map { cycle in
            let elapsed = (max(0, age) + cycle.firstCycleTimeOffset).truncatingRemainder(dividingBy: cycle.period)
            return min(cycle.distance, max(0, elapsed - cycle.startHold) * MarqueeMath.pointsPerSecond)
        } ?? 0
        let fade = MarqueeMath.trailingFadeWidth(configured: 12, contentWidth: fullWidth, containerWidth: width, offset: offset)

        let label = ink.font(Font(font)).lineLimit(1)
        Group {
            if rainbow {
                LinearGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .purple],
                               startPoint: .leading, endPoint: .trailing)
                    .mask(label)
                    .frame(width: fullWidth, height: font.ascender - font.descender)
            } else {
                label.fixedSize(horizontal: true, vertical: false)
            }
        }
        .offset(x: -offset)
        .frame(width: width, alignment: cycle == nil ? alignment : .leading)
        .clipped()
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
        }
        .accessibilityLabel(text)
    }
}

struct MenuLyricsView: View {
    let preferences: Preferences
    let frame: SurfaceFrame
    let font: NSFont
    var iconOnly = false
    var preview = false

    private var content: (text: String, sub: String?, words: [SyncedLyricWord], age: Double) {
        guard preferences.menuEnabled, !iconOnly, let track = frame.track, track.playing || preview else {
            return ("", nil, [], 0)
        }
        switch preferences.menuContent {
        case .title: return (track.title, nil, [], frame.changedAgo)
        case .titleArtist:
            return ([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " — "), nil, [], frame.changedAgo)
        case .lyrics, .translation: break
        }
        guard let line = frame.line else {
            return (preferences.menuTitleWithoutLyrics ? track.title : "", nil, [], frame.changedAgo)
        }
        let age = Double(frame.lyricPosition - line.startMs) / 1000
        if preferences.menuContent == .translation {
            return (line.translation ?? line.text, nil, [], age)
        }
        let sub: String?
        switch preferences.menuSecondary {
        case .nextLine: sub = frame.next
        case .translation: sub = line.translation
        case .off, .inlineTranslation: sub = nil
        }
        if preferences.menuSecondary == .inlineTranslation, let translation = line.translation {
            return (line.text + "  " + translation, nil,
                    preferences.menuKaraoke ? line.words + [SyncedLyricWord(text: "  " + translation, startMs: 0, durationMs: 0)] : [], age)
        }
        return (line.text, sub, preferences.menuKaraoke ? line.words : [], age)
    }

    var body: some View {
        let value = content
        let text = String(value.text.prefix(preferences.menuMaxCharacters))
        let sub = value.sub.map { String($0.prefix(preferences.menuMaxCharacters)) }
        let words = text == value.text ? value.words : []
        let subFont = NSFont(descriptor: font.fontDescriptor, size: min(9, font.pointSize * 0.75)) ?? font
        let desired = max(textWidth(text, font: font), textWidth(sub ?? "", font: subFont))
        let width = preferences.menuFixedWidth ? preferences.menuWidth : min(preferences.menuWidth, desired)
        let fill = hexColor(preferences.menuFillColor) ?? hexColor(preferences.menuTextColor) ?? .primary
        let waveform = Waveform(size: preferences.menuIconSize.points,
                                animates: preferences.menuIconAnimates && (frame.track?.playing == true || preview))
        HStack(spacing: 4) {
            if text.isEmpty || preferences.menuIconPosition == .leading { waveform }
            if !text.isEmpty {
                VStack(spacing: 0) {
                    let mainFont = sub == nil ? font : (NSFont(descriptor: font.fontDescriptor, size: min(font.pointSize, 11)) ?? font)
                    LyricText(text: text, words: words, position: frame.lyricPosition, age: value.age,
                              font: mainFont, width: width, alignment: preferences.menuAlignment.alignment,
                              fill: fill, unsung: hexColor(preferences.menuTextColor), rainbow: preferences.menuRainbow)
                    if let sub {
                        LyricText(text: sub, words: [], position: 0, age: value.age, font: subFont,
                                  width: width, alignment: preferences.menuAlignment.alignment,
                                  fill: (hexColor(preferences.menuTextColor) ?? .primary).opacity(0.68), unsung: nil, rainbow: false)
                    }
                }
            }
            if !text.isEmpty && preferences.menuIconPosition == .trailing { waveform }
        }
        .padding(.horizontal, 3)
    }
}

struct IslandView: View {
    let preferences: Preferences
    let frame: SurfaceFrame
    let font: NSFont
    let artwork: NSImage?
    let coverTint: Color?
    let notchWidth: CGFloat
    let topHeight: CGFloat
    let expanded: Bool
    let collapsed: Bool
    var onHover: (Bool) -> Void = { _ in }
    var onOffset: (Int) -> Void = { _ in }
    @State private var hovering = false

    private var foreground: Color {
        let style = expanded ? preferences.islandExpandedStyle ?? preferences.islandStyle : preferences.islandStyle
        return style == .coverArt ? coverTint ?? .white : .white
    }

    private var lyricsVisible: Bool {
        preferences.islandShowLyrics && !collapsed
            && (!preferences.islandCollapseWithoutLyrics || frame.line != nil)
    }

    var body: some View {
        let corner = expanded ? preferences.islandExpandedCorner : preferences.islandCorner
        let shape = NotchHangingShape(bottomCornerRadius: corner > 0 ? corner : nil,
                                      notchHeight: topHeight)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ear(preferences.islandLeftEar, side: .left)
                Color.clear.frame(width: notchWidth)
                ear(preferences.islandRightEar, side: .right)
            }
            .frame(height: topHeight)
            if expanded { trackHeader }
            if lyricsVisible {
                if expanded && preferences.islandExpandedLyricList && frame.index != nil {
                    expandedList
                } else {
                    lyricRow
                }
            }
            if expanded && preferences.islandExpandedOffset {
                offsetRow
            }
        }
        .background { background }
        .overlay {
            if preferences.islandProgress != .off {
                GeometryReader { geometry in
                    if preferences.islandProgress == .ears {
                        ZStack {
                            ForEach([false, true], id: \.self) { mirror in
                                NotchEarProgressShape(card: shape, notchWidth: notchWidth, notchHeight: topHeight,
                                                      cardSize: geometry.size, mirrored: mirror)
                                    .trim(from: 0, to: frame.progress)
                                    .stroke(foreground.opacity(0.82), lineWidth: 1.5)
                            }
                        }
                    } else {
                        Capsule().fill(foreground.opacity(0.82))
                            .frame(width: (geometry.size.width - 28) * frame.progress, height: 1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(.horizontal, 14)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .foregroundStyle(foreground)
        .onHover { value in
            hovering = value
            onHover(value)
        }
    }

    private func cover(_ size: CGFloat) -> some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 4))
    }

    private func ear(_ content: EarContent, side: Side) -> some View {
        HStack(spacing: 3) {
            if side == .right && preferences.islandEqualizer && preferences.islandEqualizerSide == side {
                Waveform(size: 12, animates: frame.track?.playing == true)
            }
            if collapsed {
                if side == .left { cover(min(22, topHeight - 6)) }
            } else {
                switch content {
                case .none: EmptyView()
                case .artwork: cover(min(22, topHeight - 6))
                case .title: Text(frame.track?.title ?? "")
                case .artist: Text(frame.track?.artist ?? "")
                case .album: Text(frame.track?.album ?? "")
                case .elapsed: Text(clock(frame.position))
                case .remaining: Text("−" + clock(max(0, Int((frame.track?.duration ?? 0) * 1000) - frame.position)))
                case .player: Image(systemName: "music.note")
                }
            }
            if side == .left && preferences.islandEqualizer && preferences.islandEqualizerSide == side {
                Waveform(size: 12, animates: frame.track?.playing == true)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    private func clock(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder private var background: some View {
        switch expanded ? preferences.islandExpandedStyle ?? preferences.islandStyle : preferences.islandStyle {
        case .solidBlack: Color.black
        case .frostedGlass: Rectangle().fill(.thickMaterial).environment(\.colorScheme, .dark)
        case .darkGradient: LinearGradient(colors: [.black, Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
        case .coverArt: LinearGradient(colors: [.black, (coverTint ?? .gray).opacity(0.27)], startPoint: .top, endPoint: .bottom)
            .background(.black)
        }
    }

    private var trackHeader: some View {
        HStack(spacing: 10) {
            if preferences.islandExpandedArtwork { cover(44) }
            VStack(alignment: .leading, spacing: 3) {
                if preferences.islandExpandedTitle {
                    Text(frame.track?.title ?? "").font(.system(size: 15, weight: .semibold))
                }
                if preferences.islandExpandedArtist { Text(frame.track?.artist ?? "") }
                if preferences.islandExpandedAlbum { Text(frame.track?.album ?? "") }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
    }

    private var lyricRow: some View {
        let drop = preferences.islandTrackDrop && frame.changedAgo < 2.8 && !expanded
        let line = drop ? nil : frame.line
        let text = line?.text ?? frame.track?.title ?? ""
        let secondary = preferences.islandSecondary
        let sub = secondary == .translation ? line?.translation
            : secondary == .nextLine && (!expanded || preferences.islandExpandedNextLine) && line != nil ? frame.next : nil
        return HStack(spacing: 6) {
            if preferences.islandLyricArtwork && preferences.islandLyricArtworkSide == .left { cover(24) }
            GeometryReader { geometry in
                VStack(spacing: 1) {
                    lineText(text, line: line, width: geometry.size.width)
                    if let sub {
                        Text(sub).font(.system(size: max(9, font.pointSize * 0.8))).opacity(0.66).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: preferences.islandAlignment?.alignment ?? .center)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            if preferences.islandLyricArtwork && preferences.islandLyricArtworkSide == .right { cover(24) }
        }
        .padding(.horizontal, 14)
        .frame(height: max(preferences.islandRowHeight, font.pointSize + (sub == nil ? 7 : 18)))
        .opacity(preferences.islandFadeOnHover && hovering && !expanded ? 0.28 : 1)
    }

    private var expandedList: some View {
        let lines = frame.layout.lines
        let index = frame.index ?? 0
        let count = preferences.islandListLines
        let first = max(0, index - count / 2)
        let end = min(lines.count, preferences.islandExpandedNextLine ? first + count : index + 1)
        return GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(first..<end, id: \.self) { row in
                    let line = lines[row]
                    VStack(spacing: 1) {
                        lineText(line.text, line: row == index ? line : nil, width: geometry.size.width)
                            .opacity(row == index ? 1 : 0.45)
                        if row == index, preferences.islandSecondary == .translation, let translation = line.translation {
                            Text(translation).font(.system(size: max(9, font.pointSize * 0.8))).opacity(0.68).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: CGFloat(end - first) * (font.pointSize + 7) + (preferences.islandSecondary == .translation ? 15 : 0))
    }

    private func lineText(_ text: String, line: LyricLine?, width: CGFloat) -> some View {
        LyricText(text: text, words: preferences.islandKaraoke ? line?.words ?? [] : [],
                  position: frame.lyricPosition,
                  age: line.map { Double(frame.lyricPosition - $0.startMs) / 1000 } ?? frame.changedAgo,
                  font: font, width: width, alignment: preferences.islandAlignment?.alignment ?? (expanded ? .leading : .center),
                  fill: foreground, unsung: nil, rainbow: preferences.islandColor == .rainbow)
    }

    private var offsetRow: some View {
        HStack(spacing: 8) {
            Button { onOffset(-100) } label: { Image(systemName: "minus") }
            Text(preferences.label("歌词偏移", "Lyric offset"))
            Button { onOffset(100) } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.bottom, 7)
    }
}
