import AppKit
import BodianCore
import Combine
import CoreImage
import ServiceManagement
import SwiftUI

struct Track: Decodable, Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let anchorElapsedTime: Double
    let timestamp: Double
    let playbackRate: Double
    let playing: Bool

    var anchor: ProgressAnchor {
        ProgressAnchor(durationMs: Int(duration * 1000), progressMs: Int(anchorElapsedTime * 1000),
                       rate: playing ? playbackRate : 0,
                       progressTs: timestamp > 0 ? Int(timestamp * 1000) : nil)
    }
}

struct Playback: Decodable, Equatable {
    let running: Bool
    let track: Track?
    let id: String
}

struct LyricLine: Equatable {
    let startMs: Int
    let endMs: Int
    let text: String
    let words: [SyncedLyricWord]
    let translation: String?
}

extension LyricLine: Decodable {}

struct ParsedLyrics: Decodable {
    let lines: [LyricLine]?
}

enum Surface: Hashable {
    case menu, island, expanded
}

struct LyricLayout {
    let lines: [LyricLine]

    init(_ lines: [LyricLine], width: CGFloat, font: NSFont, secondary: SecondaryLine, options: LineBreakOptions) {
        let main = LineLayoutBudget.Row(maxWidth: width) { textWidth($0, font: font) }
        let small = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * 0.8) ?? font
        let sub = LineLayoutBudget.Row(maxWidth: width) { textWidth($0, font: small) }
        let budget = LineLayoutBudget(main: main, preview: secondary == .nextLine ? sub : nil,
                                      translation: [.translation, .inlineTranslation].contains(secondary) ? sub : nil)
        let script = LyricScript.detect(song: lines.map(\.text).joined(separator: "\n"))
        let input = lines.enumerated().map { i, line in
            let next = i + 1 < lines.count ? lines[i + 1].startMs : nil
            return LyricsSegmenter.Line(startMs: line.startMs, nextStartMs: next, text: line.text,
                                        words: line.words.isEmpty ? nil : KaraokeFill.tailClamped(line.words, nextLineStartMs: next),
                                        translation: line.translation, sungEndMs: line.endMs,
                                        mergeable: next.map { line.endMs - $0 < 500 } ?? true,
                                        gapAfter: next.map { $0 - line.endMs >= 6000 } ?? false,
                                        script: LyricScript.detect(line: line.text, song: script))
        }
        self.lines = LyricsSegmenter.segments(input, budget: budget, options: options).map { segment in
            let first = lines[segment.firstLine]
            if let part = segment.part {
                return LyricLine(startMs: part.startMs, endMs: first.endMs, text: part.text,
                                 words: part.estimated ? [] : part.words, translation: part.translation ?? first.translation)
            }
            let range = lines[segment.firstLine...segment.lastLine]
            let words = input[segment.firstLine...segment.lastLine].enumerated().flatMap { index, line in
                (index > 0 ? [SyncedLyricWord(text: " ", startMs: line.startMs, durationMs: 0)] : []) + (line.words ?? [])
            }
            let translation = range.compactMap(\.translation).joined(separator: " ")
            return LyricLine(startMs: first.startMs, endMs: range.last!.endMs,
                             text: range.map(\.text).joined(separator: " "), words: words,
                             translation: translation.isEmpty ? nil : translation)
        }
    }

    func activeIndex(at position: Int) -> Int? {
        guard let last = lines.last, position < last.endMs else { return nil }
        return lines.lastIndex { $0.startMs <= position }
    }
}

@MainActor
final class PlaybackModel: ObservableObject {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Bodian Lyrics", isDirectory: true)

    private let backgroundService = SMAppService.agent(plistName: "me.taulee.bodianlyrics.engine.plist")
    @Published private(set) var backgroundStatus: SMAppService.Status = .notRegistered

    @Published var preferences: Preferences {
        didSet {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: "preferences")
                if oldValue.followLaunch != preferences.followLaunch { try saveFollowLaunch() }
            } catch {
                NSLog("%@", error.localizedDescription)
            }
            updateLayouts()
        }
    }
    @Published private(set) var playback = Playback(running: false, track: nil, id: "")
    @Published private(set) var layouts: [Surface: LyricLayout] = [:]
    @Published private(set) var artwork: NSImage?
    @Published private(set) var coverTint: Color?
    @Published private(set) var trackChangedAt = Date.distantPast
    private var lines: [LyricLine] = []
    private var playbackStamp: Date?
    private var lyricsStamp: Date?
    private var coverStamp: Date?
    private var lastTrackTitle = ""
    private var lastTrackArtist = ""

    init() {
        if let data = UserDefaults.standard.data(forKey: "preferences") {
            do {
                preferences = try JSONDecoder().decode(Preferences.self, from: data)
            } catch {
                NSLog("%@", error.localizedDescription)
                preferences = Preferences()
            }
        } else {
            preferences = Preferences()
        }
        updateLayouts()
    }

    func refreshBackgroundStatus() {
        let status = backgroundService.status
        if status != backgroundStatus { backgroundStatus = status }
    }

    func enableBackgroundService() throws {
        defer { refreshBackgroundStatus() }
        try saveFollowLaunch()
        try backgroundService.register()
    }

    private func saveFollowLaunch() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try String(preferences.followLaunch).write(to: Self.directory.appendingPathComponent("follow-launch"),
                                                   atomically: true, encoding: .utf8)
    }

    func readPlayback() {
        let url = Self.directory.appendingPathComponent("playback.json")
        if let stamp = modified(url), playbackStamp != stamp {
            do {
                let next = try JSONDecoder().decode(Playback.self, from: Data(contentsOf: url))
                if next.id != playback.id {
                    lyricsStamp = nil
                    coverStamp = nil
                    artwork = nil
                    coverTint = nil
                    lines = []
                    updateLayouts()
                }
                if let track = next.track, track.title != lastTrackTitle || track.artist != lastTrackArtist {
                    lastTrackTitle = track.title
                    lastTrackArtist = track.artist
                    trackChangedAt = Date()
                }
                playback = next
                playbackStamp = stamp
            } catch {
                NSLog("%@", error.localizedDescription)
            }
        }
        guard !playback.id.isEmpty else { return }
        let folder = Self.directory.appendingPathComponent("Parsed")
        let lyrics = folder.appendingPathComponent(playback.id + ".json")
        if let stamp = modified(lyrics), stamp != lyricsStamp {
            do {
                lines = try JSONDecoder().decode(ParsedLyrics.self, from: Data(contentsOf: lyrics)).lines ?? []
                lyricsStamp = stamp
                updateLayouts()
            } catch {
                NSLog("%@", error.localizedDescription)
            }
        }
        let cover = folder.appendingPathComponent(playback.id + ".cover")
        if let stamp = modified(cover), stamp != coverStamp {
            artwork = NSImage(contentsOf: cover)
            coverTint = artwork.flatMap(Self.averageColor)
            coverStamp = stamp
        }
    }

    private func modified(_ url: URL) -> Date? {
        do {
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            NSLog("%@", error.localizedDescription)
            return nil
        }
    }

    func font(for surface: Surface) -> NSFont {
        let p = preferences
        if surface == .menu {
            return lyricFont(family: p.menuFontFamily, size: p.menuFontSize == 0 ? 13 : p.menuFontSize, weight: p.menuFontWeight.weight)
        }
        return lyricFont(family: p.islandFontFamily, size: p.islandFontSize, weight: p.islandFontWeight.weight)
    }

    func width(for surface: Surface) -> CGFloat {
        let p = preferences
        switch surface {
        case .menu: return p.menuWidth
        case .island: return p.islandWidth - 28 - (p.islandLyricArtwork ? 32 : 0)
        case .expanded: return p.islandExpandedWidth - 36
        }
    }

    private func updateLayouts() {
        let p = preferences
        let options = LineBreakOptions(splitsLongLines: p.splitLongLines, mergesShortLines: p.mergeShortLines)
        layouts = Dictionary(uniqueKeysWithValues: [Surface.menu, .island, .expanded].map { surface in
            (surface, LyricLayout(lines, width: width(for: surface), font: font(for: surface),
                                  secondary: surface == .menu ? p.menuSecondary : p.islandSecondary, options: options))
        })
    }

    private static func averageColor(_ image: NSImage) -> Color? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        let input = CIImage(cgImage: cgImage)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Color(red: Double(pixel[0]) / 510 + 0.5, green: Double(pixel[1]) / 510 + 0.5, blue: Double(pixel[2]) / 510 + 0.5)
    }
}
