import AppKit
import BodianCore
import Combine
import Security
import ServiceManagement

struct LyricLayout {
    struct Line {
        let startMs: Int
        let endMs: Int
        let text: MenuText
    }

    let lines: [Line]
    let contentWidth: CGFloat

    init(_ lines: [LyricLine], preferences: Preferences) {
        let font = preferences.menuFont
        let options = LineBreakOptions(splitsLongLines: preferences.splitLongLines,
                                       mergesShortLines: preferences.mergeShortLines)
        let main = LineLayoutBudget.Row(maxWidth: preferences.menuWidth) { textWidth($0, font: font) }
        let budget = LineLayoutBudget(main: main, preview: nil, translation: nil)
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
        let measured = LyricsSegmenter.segments(input, budget: budget, options: options).map { segment -> Line in
            let first = lines[segment.firstLine]
            if let part = segment.part {
                let text = MenuText(part.text, words: part.estimated ? [] : part.words, font: font,
                                    characterLimit: preferences.menuMaxCharacters)
                return Line(startMs: part.startMs, endMs: first.endMs, text: text)
            }
            let range = lines[segment.firstLine...segment.lastLine]
            let words = input[segment.firstLine...segment.lastLine].enumerated().flatMap { index, line in
                (index > 0 ? [SyncedLyricWord(text: " ", startMs: line.startMs, durationMs: 0)] : []) + (line.words ?? [])
            }
            let text = MenuText(range.map(\.text).joined(separator: " "), words: words, font: font,
                                characterLimit: preferences.menuMaxCharacters)
            return Line(startMs: first.startMs, endMs: range.last!.endMs, text: text)
        }
        self.lines = measured
        contentWidth = measured.map(\.text.width).max() ?? 0
    }

    func activeIndex(at position: Int) -> Int? {
        guard let last = lines.last, position < last.endMs else { return nil }
        return lines.lastIndex { $0.startMs <= position }
    }
}

@MainActor
final class PlaybackModel: ObservableObject {
    static let directory = BodianFiles.directory
    private static let registeredEngineSignatureKey = "registeredEngineSignature"

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
            updateLayout()
        }
    }
    @Published private(set) var playback = Playback(running: false, track: nil, id: "")
    private(set) var lyricClock: LyricPlaybackClock?
    @Published private(set) var layout: LyricLayout
    @Published private(set) var trackChangedAt = Date.distantPast
    private var lines: [LyricLine] = []
    private var playbackStamp: Date?
    private var lyricsStamp: Date?
    private var lastTrackTitle = ""
    private var lastTrackArtist = ""

    var lyricOffsetSongID: String? {
        playback.track != nil && !playback.id.isEmpty ? playback.id : nil
    }

    var lyricOffset: Int? {
        lyricOffsetSongID.map { preferences.offsets[$0, default: 0] }
    }

    var globalLyricOffset: Int {
        preferences.globalLyricOffset ?? 0
    }

    var effectiveLyricOffset: Int {
        globalLyricOffset + (lyricOffset ?? 0)
    }

    func adjustLyricOffset(_ action: LyricOffsetAction) {
        guard let id = lyricOffsetSongID else { return }
        let previous = preferences.offsets[id, default: 0]
        let offset = action.applying(to: previous)
        guard previous != offset else { return }
        preferences.offsets[id] = offset == 0 ? nil : offset
    }

    func adjustGlobalLyricOffset(_ action: LyricOffsetAction) {
        let offset = action.applying(to: globalLyricOffset)
        preferences.globalLyricOffset = offset == 0 ? nil : offset
    }

    init() {
        let preferences: Preferences
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
        self.preferences = preferences
        layout = LyricLayout([], preferences: preferences)
    }

    func refreshBackgroundStatus() {
        let status = backgroundService.status
        if status != backgroundStatus { backgroundStatus = status }
    }

    func enableBackgroundService() throws {
        try registerBackgroundService(signature: engineSignature(), replacing: false)
    }

    func restartBackgroundService() async throws {
        refreshBackgroundStatus()
        guard backgroundStatus == .enabled else { return }
        let signature = try engineSignature()
        try saveFollowLaunch()
        defer { refreshBackgroundStatus() }
        try await backgroundService.unregister()
        try registerBackgroundService(signature: signature)
    }

    func updateBackgroundRegistration() throws {
        refreshBackgroundStatus()
        guard backgroundStatus == .enabled else { return }
        let signature = try engineSignature()
        guard signature != UserDefaults.standard.data(forKey: Self.registeredEngineSignatureKey) else { return }
        // 临时签名的后台换版后，系统原先登记的签名会阻止新版启动。
        try registerBackgroundService(signature: signature, replacing: true)
    }

    private func registerBackgroundService(signature: Data, replacing: Bool) throws {
        defer { refreshBackgroundStatus() }
        try saveFollowLaunch()
        if replacing { try backgroundService.unregister() }
        try registerBackgroundService(signature: signature)
    }

    private func registerBackgroundService(signature: Data) throws {
        try backgroundService.register()
        UserDefaults.standard.set(signature, forKey: Self.registeredEngineSignatureKey)
    }

    private func engineSignature() throws -> Data {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bodian-lyrics-engine")
        var code: SecStaticCode?
        let codeStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard codeStatus == errSecSuccess, let code else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(codeStatus))
        }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(infoStatus))
        }
        guard let signature = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecCSUnsigned))
        }
        return signature
    }

    private func saveFollowLaunch() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try String(preferences.followLaunch).write(to: BodianFiles.followLaunch,
                                                   atomically: true, encoding: .utf8)
    }

    func readPlayback() {
        let url = BodianFiles.playback
        if let stamp = modified(url), playbackStamp != stamp {
            do {
                let next = try JSONDecoder().decode(Playback.self, from: Data(contentsOf: url))
                let changedSongID = next.id != playback.id
                if changedSongID {
                    lyricsStamp = nil
                    lines = []
                    updateLayout()
                }
                if let track = next.track, track.title != lastTrackTitle || track.artist != lastTrackArtist {
                    lastTrackTitle = track.title
                    lastTrackArtist = track.artist
                    trackChangedAt = Date()
                }
                if let track = next.track {
                    let sameTrack = track.matchesSong(playback.track) && (!changedSongID || playback.id.isEmpty)
                    lyricClock = LyricPlaybackClock(anchor: track.anchor, previous: sameTrack ? lyricClock : nil, now: .now)
                } else {
                    lyricClock = nil
                }
                playback = next
                playbackStamp = stamp
                if changedSongID { readLyrics() }
            } catch {
                NSLog("%@", error.localizedDescription)
            }
        }
    }

    func readLyrics() {
        guard !playback.id.isEmpty else { return }
        let folder = BodianFiles.parsed
        let lyrics = folder.appendingPathComponent(playback.id + ".json")
        if let stamp = modified(lyrics), stamp != lyricsStamp {
            do {
                lines = try JSONDecoder().decode(ParsedLyrics.self, from: Data(contentsOf: lyrics)).lines
                lyricsStamp = stamp
                updateLayout()
            } catch {
                NSLog("%@", error.localizedDescription)
            }
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

    private func updateLayout() {
        layout = LyricLayout(lines, preferences: preferences)
    }
}
