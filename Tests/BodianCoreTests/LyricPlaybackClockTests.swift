import BodianCore
import Foundation
import XCTest

final class LyricPlaybackClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testSmallAnchorCorrectionsStayContinuousAndConverge() {
        let refresh = start.addingTimeInterval(0.75)
        let old = LyricPlaybackClock(anchor: anchor(10_000, at: start), previous: nil, now: start)

        for shift in [-550, 450] {
            let newAnchor = anchor(10_750 + shift, at: refresh)
            let updated = LyricPlaybackClock(anchor: newAnchor, previous: old, now: refresh)
            var lastPosition = old.position(at: refresh)
            XCTAssertEqual(updated.position(at: refresh), lastPosition)
            for frame in 1...180 {
                let date = refresh.addingTimeInterval(Double(frame) / 60)
                let position = updated.position(at: date)
                XCTAssertGreaterThanOrEqual(position, lastPosition)
                lastPosition = position
            }
            XCTAssertEqual(lastPosition, newAnchor.extrapolatedPositionMs(now: refresh.addingTimeInterval(3)))
        }
    }

    func testSeekAndPauseTakeEffectImmediately() {
        let refresh = start.addingTimeInterval(0.75)
        let old = LyricPlaybackClock(anchor: anchor(10_000, at: start), previous: nil, now: start)
        for position in [2_000, 40_000] {
            let seek = LyricPlaybackClock(anchor: anchor(position, at: refresh), previous: old, now: refresh)
            XCTAssertEqual(seek.position(at: refresh), position)
        }

        let paused = LyricPlaybackClock(anchor: anchor(10_500, at: refresh, rate: 0), previous: old, now: refresh)
        XCTAssertEqual(paused.position(at: refresh.addingTimeInterval(3)), 10_500)
    }

    private func anchor(_ position: Int, at date: Date, rate: Double = 1) -> ProgressAnchor {
        ProgressAnchor(durationMs: 100_000, progressMs: position, rate: rate,
                       progressTs: Int(date.timeIntervalSince1970 * 1_000))
    }
}
