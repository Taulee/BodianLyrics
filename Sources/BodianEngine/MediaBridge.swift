import BodianCore
import Foundation

struct MediaBridge {
    let resources: URL

    struct Snapshot: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let anchorElapsedTime: Double?
        let timestamp: Double?
        let playbackRate: Double?
        let playing: Bool?

        var track: Track {
            Track(title: Self.clean(title), artist: Self.clean(artist), album: Self.clean(album),
                  duration: duration ?? 0, anchorElapsedTime: anchorElapsedTime ?? 0,
                  timestamp: timestamp ?? 0, playbackRate: playbackRate ?? 0, playing: playing ?? false)
        }

        private static func clean(_ text: String?) -> String {
            String(String.UnicodeScalarView((text ?? "").unicodeScalars.filter {
                $0.properties.generalCategory != .format
            })).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func read() throws -> Snapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resources.appendingPathComponent("nowplaying.pl").path,
                             resources.appendingPathComponent("libnowplaying.dylib").path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "MediaRemote", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "MediaRemote bridge exited with status \(process.terminationStatus)."])
        }
        return try JSONDecoder().decode(Snapshot?.self, from: data)
    }
}
