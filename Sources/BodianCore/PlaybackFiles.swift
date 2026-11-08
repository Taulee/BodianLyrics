import Foundation

public enum BodianFiles {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Bodian Lyrics", isDirectory: true)
    public static let parsed = directory.appendingPathComponent("Parsed", isDirectory: true)
    public static let playback = directory.appendingPathComponent("playback.json")
    public static let followLaunch = directory.appendingPathComponent("follow-launch")
}

public struct Track: Codable, Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let anchorElapsedTime: Double
    public let timestamp: Double
    public let playbackRate: Double
    public let playing: Bool

    public init(title: String, artist: String, album: String, duration: Double, anchorElapsedTime: Double,
                timestamp: Double, playbackRate: Double, playing: Bool) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.anchorElapsedTime = anchorElapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.playing = playing
    }

    public var anchor: ProgressAnchor {
        ProgressAnchor(durationMs: Int(duration * 1000), progressMs: Int(anchorElapsedTime * 1000),
                       rate: playing ? playbackRate : 0,
                       progressTs: timestamp > 0 ? Int(timestamp * 1000) : nil)
    }

    public func matchesSong(_ other: Track?) -> Bool {
        title == other?.title && artist == other?.artist && album == other?.album && duration == other?.duration
    }
}

public struct Playback: Codable, Equatable {
    public let running: Bool
    public let track: Track?
    public let id: String

    public init(running: Bool, track: Track?, id: String) {
        self.running = running
        self.track = track
        self.id = id
    }

    public func shouldPublish(after previous: Self, writtenAt: Date, now: Date) -> Bool {
        guard self != previous else { return false }
        guard running == previous.running, id == previous.id,
              let track, let old = previous.track, track.matchesSong(old),
              track.playing == old.playing, track.playbackRate == old.playbackRate else { return true }

        let anchor = track.anchor
        let oldAnchor = old.anchor
        guard anchor.rate > 0, anchor.progressTs != nil, oldAnchor.progressTs != nil else {
            return track.anchorElapsedTime != old.anchorElapsedTime || anchor.progressTs != oldAnchor.progressTs && anchor.rate > 0
        }
        let drift = abs(anchor.extrapolatedPositionMs(now: now) - oldAnchor.extrapolatedPositionMs(now: now))
        return drift > LyricPlaybackClock.jitterToleranceMs || now.timeIntervalSince(writtenAt) >= 3
    }
}

public struct LyricLine: Codable, Equatable {
    public let startMs: Int
    public var endMs: Int
    public let text: String
    public let words: [SyncedLyricWord]
    public var translation: String?

    public init(startMs: Int, endMs: Int, text: String, words: [SyncedLyricWord], translation: String? = nil) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.words = words
        self.translation = translation
    }
}

public struct ParsedLyrics: Codable {
    public let modified: String
    public let size: Int64
    public let lines: [LyricLine]

    public init(modified: String, size: Int64, lines: [LyricLine]) {
        self.modified = modified
        self.size = size
        self.lines = lines
    }
}
