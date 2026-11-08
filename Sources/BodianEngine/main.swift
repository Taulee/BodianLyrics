import AppKit
import BodianCore
import Foundation

final class Engine {
    private static let playerBundle = "cn.wenyu.bodian.bodianPc"
    private static let lyricsBundle = "me.taulee.bodianlyrics"
    private let workspace = NSWorkspace.shared
    private let queue = DispatchQueue(label: "BodianLyrics.playback")
    private let app: URL
    private let library: BodianLibrary
    private let cache: LyricCache
    private let media: MediaBridge
    private var observation: NSKeyValueObservation?
    private var timer: DispatchSourceTimer?
    private var pid: pid_t?
    private var previousTrack: Track?
    private var songID = ""
    private var lastState: Playback?
    private var lastWriteAt = Date.distantPast

    init() throws {
        let contents = Bundle.main.executableURL!.deletingLastPathComponent().deletingLastPathComponent()
        app = contents.deletingLastPathComponent()
        media = MediaBridge(resources: contents.appendingPathComponent("Resources"))
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/\(Self.playerBundle)", isDirectory: true)
        library = BodianLibrary(database: directory.appendingPathComponent("database/songDB.db"))
        cache = LyricCache(source: directory.appendingPathComponent("cache/lyric", isDirectory: true),
                           destination: BodianFiles.parsed)
        try FileManager.default.createDirectory(at: BodianFiles.parsed, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    func start() {
        cache.start()
        observation = workspace.observe(\.runningApplications, options: [.initial, .new]) { [weak self] workspace, _ in
            let pid = workspace.runningApplications.first { $0.bundleIdentifier == Self.playerBundle }?.processIdentifier
            self?.queue.async { [weak self] in self?.playerChanged(pid) }
        }
    }

    private func playerChanged(_ next: pid_t?) {
        guard next != pid || lastState == nil else { return }
        timer?.cancel()
        timer = nil
        pid = next
        previousTrack = nil
        songID = ""
        guard next != nil else {
            write(Playback(running: false, track: nil, id: ""))
            return
        }
        if followsPlayer() {
            DispatchQueue.main.async {
                guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.lyricsBundle).isEmpty else { return }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                self.workspace.openApplication(at: self.app, configuration: configuration) { _, error in
                    if let error { NSLog("Open Bodian Lyrics: %@", error.localizedDescription) }
                }
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(750))
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    private func followsPlayer() -> Bool {
        do {
            return try String(contentsOf: BodianFiles.followLaunch, encoding: .utf8) == "true"
        } catch CocoaError.fileReadNoSuchFile {
            return true
        } catch {
            NSLog("Follow launch: %@", error.localizedDescription)
            return false
        }
    }

    private func poll() {
        var current: Track?
        do {
            current = try media.read()?.track
        } catch {
            NSLog("Now playing: %@", error.localizedDescription)
        }
        guard let track = current, !track.title.isEmpty else {
            write(Playback(running: true, track: nil, id: ""))
            return
        }
        if !track.matchesSong(previousTrack) || songID.isEmpty {
            do {
                songID = try library.songID(for: track)
            } catch {
                songID = ""
                NSLog("Song history: %@", error.localizedDescription)
            }
        }
        previousTrack = track
        write(Playback(running: true, track: track, id: songID))
    }

    private func write(_ state: Playback) {
        let now = Date()
        if let lastState, !state.shouldPublish(after: lastState, writtenAt: lastWriteAt, now: now) { return }
        do {
            try JSONEncoder().encode(state).write(to: BodianFiles.playback, options: .atomic)
            lastState = state
            lastWriteAt = now
        } catch {
            NSLog("Playback state: %@", error.localizedDescription)
        }
    }
}

do {
    let engine = try Engine()
    engine.start()
    withExtendedLifetime(engine) { RunLoop.main.run() }
} catch {
    NSLog("Bodian Lyrics engine: %@", error.localizedDescription)
    exit(EXIT_FAILURE)
}
