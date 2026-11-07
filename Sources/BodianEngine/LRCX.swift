import BodianCore
import Foundation

enum LRCX {
    private static let key = Array("BD1BYDH79nXZ".utf16)
    private static let header = try! NSRegularExpression(pattern: #"^\[kuwo:([0-9]+)"#)
    private static let linePattern = try! NSRegularExpression(pattern: #"^\[([0-9]{1,3}):([0-9]{2})(?:\.([0-9]{1,3}))?\](.*)$"#)
    private static let wordPattern = try! NSRegularExpression(pattern: #"<(-?[0-9]+),(-?[0-9]+)(?:,-?[0-9]+)?>"#)

    static func parse(_ raw: String) -> [LyricLine] {
        let decoded = String(decoding: raw.utf16.enumerated().map { index, unit in
            unit ^ key[index % key.count]
        }, as: UTF16.self)
        let rows = decoded.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let timing = coefficients(rows)
        var lines: [LyricLine] = []
        var translation = ""
        var translationStamp = 0
        var endMarks: [Int] = []
        for row in rows {
            let source = row as NSString
            guard let match = linePattern.firstMatch(in: row, range: NSRange(location: 0, length: source.length)) else {
                continue
            }
            let minute = Int(source.substring(with: match.range(at: 1)))!
            let second = Int(source.substring(with: match.range(at: 2)))!
            let fractionRange = match.range(at: 3)
            let fraction = fractionRange.location == NSNotFound ? "" : source.substring(with: fractionRange)
            let millis = Int(fraction.padding(toLength: 3, withPad: "0", startingAt: 0))!
            let start = (minute * 60 + second) * 1000 + millis
            let body = source.substring(with: match.range(at: 4))
            guard let timing else {
                if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    endMarks.append(start)
                } else {
                    lines.append(LyricLine(startMs: start, endMs: 0, text: body, words: []))
                }
                continue
            }
            guard let line = timedLine(body, start: start, timing: timing) else { continue }
            if line.allZero {
                translation = line.text
                translationStamp = start
                continue
            }
            // 译文的时间戳标在下一句上，展示时归到前一句。
            if translationStamp == start, !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !lines.isEmpty {
                lines[lines.count - 1].translation = translation
            }
            translation = ""
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let words = mergeWhitespace(line.words)
            let end = words.map { $0.startMs + $0.durationMs }.max() ?? 0
            lines.append(LyricLine(startMs: start, endMs: end, text: line.text, words: words))
        }
        lines.sort { $0.startMs < $1.startMs }
        if timing == nil {
            for i in lines.indices {
                let start = lines[i].startMs
                var end = start + 8000
                if i + 1 < lines.count { end = min(end, lines[i + 1].startMs) }
                for mark in endMarks where mark > start { end = min(end, mark) }
                lines[i].endMs = end
            }
        }
        return lines
    }

    private static func coefficients(_ rows: [String]) -> (Int, Int)? {
        for row in rows {
            let text = row.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = text as NSString
            guard let match = header.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else {
                continue
            }
            guard let value = Int(source.substring(with: match.range(at: 1)), radix: 8) else { return nil }
            let a = value / 10, b = value % 10
            return a != 0 && b != 0 ? (a, b) : nil
        }
        return nil
    }

    private static func timedLine(_ body: String, start: Int, timing: (Int, Int))
        -> (text: String, words: [SyncedLyricWord], allZero: Bool)? {
        let source = body as NSString
        let tokens = wordPattern.matches(in: body, range: NSRange(location: 0, length: source.length))
        guard let first = tokens.first else { return nil }
        let prefix = source.substring(to: first.range.location)
        var words: [SyncedLyricWord] = []
        var allZero = true
        for (i, token) in tokens.enumerated() {
            let a = Int(source.substring(with: token.range(at: 1))) ?? 0
            let b = Int(source.substring(with: token.range(at: 2))) ?? 0
            allZero = allZero && a == 0 && b == 0
            let from = start + abs(a + b) / (2 * timing.0)
            let duration = abs(a - b) / (2 * timing.1)
            if let last = words.last, from < last.startMs + last.durationMs {
                let trimmedStart = min(last.startMs, from)
                words[words.count - 1] = SyncedLyricWord(text: last.text, startMs: trimmedStart, durationMs: from - trimmedStart)
            }
            let textStart = NSMaxRange(token.range)
            let textEnd = i + 1 < tokens.count ? tokens[i + 1].range.location : source.length
            let text = source.substring(with: NSRange(location: textStart, length: textEnd - textStart))
            words.append(SyncedLyricWord(text: (i == 0 ? prefix : "") + text, startMs: from, durationMs: duration))
        }
        return (words.map(\.text).joined(), words, allZero)
    }

    private static func mergeWhitespace(_ words: [SyncedLyricWord]) -> [SyncedLyricWord] {
        var merged: [SyncedLyricWord] = []
        var prefix = ""
        for word in words {
            if !word.text.isEmpty, word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let last = merged.last {
                    let duration = max(last.durationMs, word.startMs + word.durationMs - last.startMs)
                    merged[merged.count - 1] = SyncedLyricWord(text: last.text + word.text, startMs: last.startMs, durationMs: duration)
                } else {
                    prefix += word.text
                }
            } else {
                merged.append(SyncedLyricWord(text: prefix + word.text, startMs: word.startMs, durationMs: word.durationMs))
                prefix = ""
            }
        }
        return merged
    }
}
