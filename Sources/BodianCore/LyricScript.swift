import Foundation

/// 分句只需知道该用中文、日文还是通用词界。
public enum LyricScript: Equatable {
    case chinese, japanese, other

    private static let kana = try! NSRegularExpression(pattern: #"\p{Hiragana}|\p{Katakana}"#)
    private static let han = try! NSRegularExpression(pattern: #"\p{Han}"#)
    private static let hangul = try! NSRegularExpression(pattern: #"\p{Hangul}"#)
    private static let kanjiLock = NSLock()
    nonisolated(unsafe) private static var kanji: [Character: Bool] = [:]

    public static func detect(song: String) -> LyricScript {
        detect(line: song, song: .other)
    }

    public static func detect(line: String, song: LyricScript) -> LyricScript {
        let range = NSRange(line.startIndex..., in: line)
        if kana.firstMatch(in: line, range: range) != nil { return .japanese }
        if hangul.firstMatch(in: line, range: range) != nil { return .other }
        guard han.firstMatch(in: line, range: range) != nil else { return .other }
        return song == .japanese && !looksChineseWritten(line) ? .japanese : .chinese
    }

    /// 日文歌里的纯汉字行沿用日文分词，含较多日文字集之外的汉字时用中文分词。
    private static func looksChineseWritten(_ line: String) -> Bool {
        var han = 0
        var foreign = 0
        for character in line where character.unicodeScalars.count == 1 && character.unicodeScalars.first!.properties.isIdeographic {
            han += 1
            if !isJapaneseKanji(character) { foreign += 1 }
        }
        return foreign >= 2 || (foreign > 0 && foreign * 4 >= han)
    }

    private static func isJapaneseKanji(_ character: Character) -> Bool {
        kanjiLock.lock()
        defer { kanjiLock.unlock() }
        if let known = kanji[character] { return known }
        let known = String(character).data(using: .shiftJIS) != nil
        kanji[character] = known
        return known
    }
}
