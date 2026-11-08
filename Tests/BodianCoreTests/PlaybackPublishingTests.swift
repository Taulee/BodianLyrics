import BodianCore
import Foundation
import XCTest

final class PlaybackPublishingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testRegularProgressWaitsForPeriodicRefresh() {
        let original = state(position: 20, date: start)
        let sample = start.addingTimeInterval(0.75)
        let jitter = state(position: 20.3, date: sample)
        XCTAssertFalse(jitter.shouldPublish(after: original, writtenAt: start, now: sample))

        let refresh = start.addingTimeInterval(3)
        let progress = state(position: 22.8, date: refresh)
        XCTAssertTrue(progress.shouldPublish(after: original, writtenAt: start, now: refresh))
        XCTAssertFalse(original.shouldPublish(after: original, writtenAt: start, now: refresh))
    }

    func testPlaybackChangesDoNotWaitForPeriodicRefresh() {
        let original = state(position: 20, date: start)
        let sample = start.addingTimeInterval(0.75)
        for changed in [state(position: 20, date: sample, playing: false),
                        state(position: 20, date: sample, id: "next"),
                        state(position: 10, date: sample),
                        state(position: 40, date: sample),
                        Playback(running: false, track: nil, id: "")] {
            XCTAssertTrue(changed.shouldPublish(after: original, writtenAt: start, now: sample))
        }

        let paused = state(position: 20, date: start, playing: false)
        XCTAssertFalse(state(position: 20, date: sample, playing: false)
            .shouldPublish(after: paused, writtenAt: start, now: sample))
        XCTAssertTrue(state(position: 21, date: sample, playing: false)
            .shouldPublish(after: paused, writtenAt: start, now: sample))
    }

    private func state(position: Double, date: Date, playing: Bool = true, id: String = "song") -> Playback {
        let track = Track(title: "Title", artist: "Artist", album: "Album", duration: 100,
                          anchorElapsedTime: position, timestamp: date.timeIntervalSince1970,
                          playbackRate: 1, playing: playing)
        return Playback(running: true, track: track, id: id)
    }
}
