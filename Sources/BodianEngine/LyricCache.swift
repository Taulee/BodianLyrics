import BodianCore
import Darwin
import Foundation

final class LyricCache {
    private let source: URL
    private let destination: URL
    private let queue = DispatchQueue(label: "BodianLyrics.cache")
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?

    init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    func start() {
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.setEventHandler { [weak self] in self?.scan() }
            self.timer = timer
            timer.resume()
            self.scan()
        }
    }

    private func watch() {
        let descriptor = open(source.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            timer?.schedule(deadline: .now() + 3, repeating: 3)
            return
        }
        let watch = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                              eventMask: [.write, .delete, .rename], queue: queue)
        watch.setEventHandler { [weak self] in
            guard let self, let watcher else { return }
            if !watcher.data.intersection([.delete, .rename]).isEmpty {
                watcher.cancel()
                self.watcher = nil
            }
            scan()
        }
        watch.setCancelHandler { close(descriptor) }
        watcher = watch
        watch.resume()
        timer?.schedule(deadline: .now() + 10, repeating: 10)
    }

    private func scan() {
        if watcher == nil { watch() }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "lrc" {
                let id = file.deletingPathExtension().lastPathComponent
                guard Int64(id) != nil, !file.hasDirectoryPath else { continue }
                do {
                    try refresh(file, destination.appendingPathComponent(id + ".json"))
                } catch {
                    NSLog("Lyric cache %@: %@", file.lastPathComponent, error.localizedDescription)
                }
            }
        } catch CocoaError.fileReadNoSuchFile {
            // 波点尚未写入歌词时，缓存目录可能还不存在。
        } catch {
            NSLog("Lyric cache: %@", error.localizedDescription)
        }
    }

    private func refresh(_ file: URL, _ output: URL) throws {
        var info = stat()
        guard stat(file.path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let seconds = info.st_mtimespec.tv_sec
        let nanos = info.st_mtimespec.tv_nsec
        let whole = Date(timeIntervalSince1970: Double(seconds)).formatted(.iso8601)
        let fraction = String(format: "%09d", Int32(nanos))
        let trimmed = String(fraction.reversed().drop(while: { $0 == "0" }).reversed())
        let modified = trimmed.isEmpty ? whole : String(whole.dropLast()) + "." + trimmed + "Z"
        do {
            let old = try JSONDecoder().decode(ParsedLyrics.self, from: Data(contentsOf: output))
            if old.size == info.st_size, old.modified == modified {
                return
            }
        } catch CocoaError.fileReadNoSuchFile {
            // 第一次解析这个歌曲 ID。
        } catch is DecodingError {
            // 缓存不可读时用源歌词重建。
        }
        let raw = try Data(contentsOf: file)
        let parsed = ParsedLyrics(modified: modified, size: info.st_size,
                                  lines: LRCX.parse(String(decoding: raw, as: UTF8.self)))
        try JSONEncoder().encode(parsed).write(to: output, options: .atomic)
    }
}
