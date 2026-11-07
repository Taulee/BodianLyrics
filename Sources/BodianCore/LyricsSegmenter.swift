import CoreGraphics
import Foundation

/// 每个显示面提供自己的文字宽度和测量方式。
public struct LineLayoutBudget {
    public struct Row {
        public let maxWidth: CGFloat
        public let measure: (String) -> CGFloat

        public init(maxWidth: CGFloat, measure: @escaping (String) -> CGFloat) {
            self.maxWidth = maxWidth
            self.measure = measure
        }
    }

    /// 主行。
    public let main: Row
    /// 这一段排成「下一句」时那一行;nil = 这个面不显示下一句。
    public let preview: Row?
    /// 译文那一行;nil = 不显示。
    public let translation: Row?
    public init(main: Row, preview: Row? = nil, translation: Row? = nil) {
        self.main = main
        self.preview = preview
        self.translation = translation
    }

    /// 同一份预算,量宽函数套上缓存:断一首歌时同一个词、同一句要量很多遍。缓存只活在这一份副本里。
    public func memoized() -> LineLayoutBudget {
        func cached(_ f: @escaping (String) -> CGFloat) -> (String) -> CGFloat {
            final class Box { var values: [String: CGFloat] = [:] }
            let box = Box()
            return { text in
                if let v = box.values[text] { return v }
                let v = f(text)
                box.values[text] = v
                return v
            }
        }
        func cachedRow(_ r: Row?) -> Row? { r.map { Row(maxWidth: $0.maxWidth, measure: cached($0.measure)) } }
        return LineLayoutBudget(
            main: Row(maxWidth: main.maxWidth, measure: cached(main.measure)),
            preview: cachedRow(preview), translation: cachedRow(translation))
    }
}

/// 单行展示面按宽度断句的两件事,各自一个开关。都关着时每一行原样一段。
public struct LineBreakOptions: Equatable, Hashable, Sendable {
    /// 放不下一行的句子拆开。开着时各面的每一行都放得下,不折行、不滚动。
    public var splitsLongLines: Bool
    public var mergesShortLines: Bool

    public init(splitsLongLines: Bool = false, mergesShortLines: Bool = false) {
        self.splitsLongLines = splitsLongLines
        self.mergesShortLines = mergesShortLines
    }

    public static let off = LineBreakOptions()
    public var isActive: Bool { splitsLongLines || mergesShortLines }
}

/// 根据显示宽度和歌词时间，拆长句或合并相邻的短句。
public enum LyricsSegmenter {
    public struct Line {
        public let startMs: Int
        /// 下一行开始的时刻;最后一行为 nil。只有逐行时间的句子拆开时,按它估每段几点开唱。
        public let nextStartMs: Int?
        public let text: String
        /// 逐字词;nil = 只有逐行时间。
        public let words: [SyncedLyricWord]?
        public let translation: String?
        /// 唱完的时刻(逐字行含背景人声;逐行歌词是句末标记);没有是 nil。
        public let sungEndMs: Int?
        /// 跟下一行真重叠的行不参与合并(它在单行展示面上另有退化形态)。
        public let mergeable: Bool
        /// 这一行后面紧跟着一段间奏点,不跨过去合并。
        public let gapAfter: Bool
        /// 用于选择分词器的文字类型。
        /// nil = 只看这一行自己的字。
        public let script: LyricScript?

        public init(startMs: Int, nextStartMs: Int? = nil, text: String, words: [SyncedLyricWord]?,
                    translation: String? = nil, sungEndMs: Int?,
                    mergeable: Bool, gapAfter: Bool, script: LyricScript? = nil) {
            self.startMs = startMs
            self.nextStartMs = nextStartMs
            self.text = text
            self.words = words
            self.translation = translation
            self.sungEndMs = sungEndMs
            self.mergeable = mergeable
            self.gapAfter = gapAfter
            self.script = script
        }
    }

    /// 一句拆开后的一段。
    public struct Part: Equatable {
        public let startMs: Int
        /// 这一段的词。`estimated` 时是只有逐行时间的句子按宽度估出来的时刻,只用来定段的起点,不拿去填色。
        public let words: [SyncedLyricWord]
        public let estimated: Bool
        /// 此段的译文。nil 表示使用整句的译文。
        public let translation: String?

        public init(startMs: Int, words: [SyncedLyricWord], estimated: Bool,
                    translation: String? = nil) {
            self.startMs = startMs
            self.words = words
            self.estimated = estimated
            self.translation = translation
        }

        public var text: String { words.map(\.text).joined() }
    }

    /// 一段显示单位:第 firstLine…lastLine 行并成的一句;`part` 非 nil 时是第 firstLine 行拆开后的一段。
    public struct Segment: Equatable {
        public let firstLine: Int
        public let lastLine: Int
        public let part: Part?

        public init(firstLine: Int, lastLine: Int, part: Part? = nil) {
            self.firstLine = firstLine
            self.lastLine = lastLine
            self.part = part
        }
    }

    /// 这一句停留不到这么久才考虑跟下一句合并。
    public static let mergeShortDwellMs = 2000
    /// 被并进来的下一句自己停留不超过这么久:长句不往短句上接。
    public static let mergeNextMaxDwellMs = 3500
    /// 「很短的一句」:停留不到 mergeShortDwellMs、而且不超过这么多字(displayWidth)。相邻两句里至少有一句是
    /// 这样的才合并,两句完整的句子只是唱得快,不往一起粘。
    public static let mergeTinyMaxWidth: Double = 4
    /// 合完从第一句开始到最后一句唱完不超过这么久。
    public static let mergeMaxSpanMs = 5000
    /// 一句最多拆成几段。到这个数还放不下,说明一行窄得放不下几个字,不再往下拆。
    public static let maxParts = 12
    /// 只有逐行时间的句子,估时长时每个词(汉字一个字算一个)最多给这么久:句子后面拖着一段没标间奏的空白时,
    /// 后半句不至于被估到很晚才出来。
    public static let estimatedMaxMsPerToken = 600
    /// 量出来的宽度比上限多不到这么多也算放得下(浮点误差)。
    static let fitTolerance: CGFloat = 0.5

    /// 每一行原样一段:不重新断句时用。
    public static func identity(lineCount: Int) -> [Segment] {
        (0..<lineCount).map { Segment(firstLine: $0, lastLine: $0) }
    }

    /// 按需取第 k 行;k 越界返回 nil。
    public typealias LineProvider = (Int) -> Line?

    public static func segments(_ lines: [Line], budget original: LineLayoutBudget,
                                options: LineBreakOptions) -> [Segment] {
        guard original.main.maxWidth > 0, options.isActive else { return identity(lineCount: lines.count) }
        let budget = original.memoized()
        let provider: LineProvider = { lines.indices.contains($0) ? lines[$0] : nil }
        var out: [Segment] = []
        var i = 0
        while i < lines.count {
            let segs = step(from: i, line: provider, budget: budget, options: options)
            out += segs
            i = (segs.last?.lastLine ?? i) + 1
        }
        return out
    }

    /// 从第 i 行断出下一组段:放不下的一句拆成的几段,或者从第 i 行起并成的一句(可能就是它自己)。只往后看
    /// 合并要看的那几行,所以从头一组一组往后断,断好的段不会因为后面的行变。`budget` 应先 `memoized()`。
    /// 不拆时放不下的句子原样一段(由各面自己折行或滚动);不并时每句一段。
    public static func step(from i: Int, line: LineProvider, budget: LineLayoutBudget,
                            options: LineBreakOptions) -> [Segment] {
        guard let first = line(i) else { return [] }
        if !fits(line, i...i, budget: budget) {
            if options.splitsLongLines, let parts = split(first, budget: budget) {
                return parts.map { Segment(firstLine: i, lastLine: i, part: $0) }
            }
            return [Segment(firstLine: i, lastLine: i)]
        }
        guard options.mergesShortLines else { return [Segment(firstLine: i, lastLine: i)] }
        var j = i
        while canMerge(line, from: i, through: j, budget: budget) { j += 1 }
        return [Segment(firstLine: i, lastLine: j)]
    }

    // MARK: - 放不放得下

    private static func mainWidth(words: [SyncedLyricWord]?, text: String, budget: LineLayoutBudget) -> CGFloat {
        let measure = budget.main.measure
        let whole = measure(text)
        guard let words else { return whole }
        return max(words.reduce(CGFloat(0)) { $0 + measure($1.text) }, whole)
    }

    static func joinedWords(_ lines: [Line]) -> [SyncedLyricWord]? {
        var out: [SyncedLyricWord] = []
        for k in lines.indices {
            guard var ws = lines[k].words else { return nil }
            if k < lines.count - 1, let tail = ws.last, tail.text.last?.isWhitespace != true,
               !mergeSeparator(after: lines[k].text, before: lines[k + 1].text, script: lines[k + 1].script).isEmpty {
                ws[ws.count - 1] = SyncedLyricWord(text: tail.text + " ", startMs: tail.startMs, durationMs: tail.durationMs)
            }
            out += ws
        }
        return out
    }

    /// 相邻两句并成一句时中间接什么:日文后一句以只会接在别的词后面的助词 / 助动词(单独给它分词的第一个词,
    /// `WordBreaks.japaneseContinuationStarts`)或行首禁则字开头时,它接着前一句(「おのおの」+「のスマイルで」),连写;
    /// 别的一律补一个空格。测量合并句和拼接合并句时都使用同一条规则。
    public static func mergeSeparator(after previous: String, before next: String, script: LyricScript?) -> String {
        let a = previous.trimmingCharacters(in: .whitespaces), b = next.trimmingCharacters(in: .whitespaces)
        guard let last = a.unicodeScalars.last, let first = b.unicodeScalars.first,
              isCJK(last), !isHangul(last) else { return " " }
        if noLineStart.contains(first) || sentencePunctuation.contains(first) { return "" }
        guard let head = b.first, WordBreaks.japaneseContinuationInitials.contains(head),
              (script ?? LyricScript.detect(line: b, song: .other)) == .japanese,
              let token = WordBreaks.firstJapaneseToken(b), WordBreaks.japaneseContinuationStarts.contains(token) else {
            return " "
        }
        return ""
    }

    static func joinedText(_ values: [String?]) -> String? {
        let parts = values.compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// 逐字句按词接，句间分隔符已放进词序列。逐行歌词使用 `mergeSeparator` 拼接。
    static func mergedText(_ lines: [Line], words: [SyncedLyricWord]?) -> String {
        if let words { return words.map(\.text).joined() }
        var out = ""
        for (k, line) in lines.enumerated() {
            if k > 0 { out += mergeSeparator(after: lines[k - 1].text, before: line.text, script: line.script) }
            out += line.text
        }
        return out
    }

    /// 第 range 这几行并成一句(或就是一句)时,这个面上的每一行是不是都放得下。
    static func fits(_ line: LineProvider, _ range: ClosedRange<Int>, budget: LineLayoutBudget) -> Bool {
        let ls = range.compactMap(line)
        guard ls.count == range.count else { return false }
        let words = joinedWords(ls)
        let text = mergedText(ls, words: words)
        let mainLimit = budget.main.maxWidth + fitTolerance
        guard mainWidth(words: words, text: text, budget: budget) <= mainLimit else { return false }
        if let row = budget.preview, row.measure(text) > row.maxWidth + fitTolerance {
            return false
        }
        if let row = budget.translation, let tr = joinedText(ls.map(\.translation)),
           row.measure(tr) > row.maxWidth + fitTolerance {
            return false
        }
        return true
    }

    /// 组 [f, j] 能不能再并进第 j+1 句。第 j+1 句的停留按下一句的起点算，它是最后一句时
    /// 按它唱完的时刻算,行级歌词的最后一句没有句末标记就不知道停多久,不并。
    static func canMerge(_ line: LineProvider, from f: Int, through j: Int, budget: LineLayoutBudget) -> Bool {
        guard let a = line(j), let b = line(j + 1), let head = line(f),
              let bEnd = line(j + 2)?.startMs ?? b.sungEndMs else { return false }
        let dwellA = b.startMs - a.startMs, dwellB = bEnd - b.startMs
        guard dwellA < mergeShortDwellMs, dwellB < mergeNextMaxDwellMs else { return false }
        let tinyA = displayWidth(a.text) <= mergeTinyMaxWidth
        let tinyB = dwellB < mergeShortDwellMs && displayWidth(b.text) <= mergeTinyMaxWidth
        guard tinyA || tinyB else { return false }
        guard !a.gapAfter, a.mergeable, b.mergeable else { return false }
        guard (a.words == nil) == (b.words == nil) else { return false }
        guard (b.sungEndMs ?? bEnd) - head.startMs <= mergeMaxSpanMs else { return false }
        return fits(line, f...(j + 1), budget: budget)
    }

    // MARK: - 拆

    /// 拆开时的一个单位:一个词，或者行级歌词按文字切出来的一截。
    private struct Unit {
        var words: [SyncedLyricWord]
        var width: CGFloat
        var text: String { words.map(\.text).joined() }
    }

    /// 把一句拆成每行都放得下的最少段数。拆不出来(一个字都放不下)返回 nil。
    static func split(_ line: Line, budget: LineLayoutBudget) -> [Part]? {
        let mainLimit = budget.main.maxWidth
        guard mainLimit > 0 else { return nil }
        let estimated = line.words == nil
        let words = line.words ?? estimatedWords(line, measure: budget.main.measure)
        guard !words.isEmpty else { return nil }
        let joinedText = words.map(\.text).joined()
        let script = line.script ?? LyricScript.detect(line: line.text, song: .other)
        let wordBreaks = WordBreaks(text: joinedText, script: script)
        var units: [Unit] = []
        for w in words {
            let width = budget.main.measure(w.text)
            if width > mainLimit + fitTolerance {
                units += exploded(w, measure: budget.main.measure)
            } else {
                units.append(Unit(words: [w], width: width))
            }
        }
        let translationLimit = budget.translation.map(\.maxWidth)
        let translationNeedsSplit = budget.translation.flatMap { row in
            line.translation.map { row.measure($0) > translationLimit! + fitTolerance }
        } ?? false
        let translationBreaks = translationNeedsSplit
            ? line.translation.flatMap { WordBreaks(text: $0, script: LyricScript.detect(line: $0, song: .other)) } : nil
        // 主行和预览都放得下时，不为了译文硬切原文。
        let textFits = mainWidth(words: words, text: line.text, budget: budget)
            <= mainLimit + fitTolerance
            && (budget.preview.map { $0.measure(line.text) <= $0.maxWidth + fitTolerance } ?? true)

        /// `hard`:false 只断在能断的地方;true 硬切(各段仍求等宽),再不行逐行装满。
        func attempt(_ units: [Unit], hard: Bool) -> [Part]? {
            guard units.count >= 2 else { return nil }
            let spaceWidth = budget.main.measure(" ")
            let widths = units.map(\.width)
            let trailing = units.map { $0.text.last?.isWhitespace == true ? spaceWidth : 0 }
            let natural = cutPenalties(units.map(\.text), wordBreaks: wordBreaks)
            let forced: [CGFloat?] = units.indices.map { c in c == 0 ? nil : (natural[c] ?? 1) }

            /// 按这组切点出各段;有一行放不下返回 nil。`balanced`:译文也按各段等宽切(段数多时改为逐行装满)。
            func build(_ starts: [Int], balanced: Bool) -> [Part]? {
                let parts = starts.count
                let ranges = starts.indices.map { k in starts[k]..<(k + 1 < starts.count ? starts[k + 1] : units.count) }
                let partUnits = ranges.map { r in trimmed(Array(units[r])) }
                let partTexts = partUnits.map { $0.flatMap(\.words).map(\.text).joined() }
                for k in partUnits.indices {
                    let ws = partUnits[k].flatMap(\.words)
                    guard mainWidth(words: ws, text: partTexts[k], budget: budget)
                        <= mainLimit + fitTolerance else { return nil }
                }
                if let row = budget.preview {
                    let previewLimit = row.maxWidth + fitTolerance
                    guard partTexts.allSatisfy({ row.measure($0) <= previewLimit }) else { return nil }
                }
                func companion(_ text: String, _ row: LineLayoutBudget.Row, _ maxWidth: CGFloat,
                               _ breaks: WordBreaks?) -> [String]? {
                    balanced ? spreadText(text, parts: parts, row: row, maxWidth: maxWidth, wordBreaks: breaks)
                             : packText(text, parts: parts, row: row, maxWidth: maxWidth, wordBreaks: breaks)
                }
                var translations: [String]?
                if translationNeedsSplit, let row = budget.translation, let tr = line.translation {
                    guard let t = companion(tr, row, translationLimit!, translationBreaks) else { return nil }
                    translations = t
                }
                return partUnits.indices.map { k in
                    let us = partUnits[k]
                    let ws = us.flatMap(\.words)
                    return Part(
                        startMs: k == 0 ? line.startMs : (ws.first?.startMs ?? line.startMs),
                        words: ws, estimated: estimated,
                        translation: translations?[k])
                }
            }

            // 段数至少要把总宽装下(每段末尾的空白不算宽),更少的不用试。
            let bare = widths.reduce(0, +) - trailing.reduce(0, +)
            let fewest = max(2, Int((bare / max(mainLimit, 1)).rounded(.up)))
            if fewest <= min(maxParts, units.count) {
                for parts in fewest...min(maxParts, units.count) {
                    guard let starts = balancedCuts(widths: widths, trailing: trailing,
                                                    penalties: hard ? forced : natural,
                                                    parts: parts, maxWidth: mainLimit) else { continue }
                    if let built = build(starts, balanced: true) { return built }
                }
            }
            guard hard else { return nil }
            // maxParts 段还放不下(整首挤在一行这类):不再求各段等宽,逐行装满。
            if let starts = packedCuts(widths: widths, trailing: trailing, penalties: natural, maxWidth: mainLimit),
               starts.count > 1, let built = build(starts, balanced: false) {
                return built
            }
            return nil
        }
        if let parts = attempt(units, hard: false) { return parts }
        let chars = words.flatMap { exploded($0, measure: budget.main.measure) }
        if chars.count > units.count, let parts = attempt(chars, hard: false) { return parts }
        if !textFits {
            if let parts = attempt(units, hard: true) { return parts }
            if chars.count > units.count, let parts = attempt(chars, hard: true) { return parts }
        }
        // 原文放得下时，截短无法随原文分段的译文。
        guard textFits else { return nil }
        return [Part(
            startMs: line.startMs, words: words, estimated: estimated,
            translation: translationNeedsSplit ? line.translation.flatMap { tr in
                budget.translation.map { truncated(tr, row: $0, maxWidth: translationLimit!) }
            } : nil)]
    }

    /// 截到放得下为止,末尾补「…」。
    static func truncated(_ text: String, row: LineLayoutBudget.Row, maxWidth: CGFloat) -> String {
        guard row.measure(text) > maxWidth + fitTolerance else { return text }
        let chars = Array(text)
        func candidate(_ n: Int) -> String {
            String(chars[0..<n]).trimmingCharacters(in: .whitespaces) + "…"
        }
        var lo = 0, hi = chars.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if row.measure(candidate(mid)) <= maxWidth + fitTolerance { lo = mid } else { hi = mid - 1 }
        }
        return candidate(lo)
    }

    /// 一段首尾的空白去掉(首单位的前导空白、末单位的尾随空白)。
    private static func trimmed(_ units: [Unit]) -> [Unit] {
        var us = units
        if var first = us.first, let w = first.words.first {
            first.words[0] = SyncedLyricWord(text: String(w.text.drop { $0.isWhitespace }),
                                             startMs: w.startMs, durationMs: w.durationMs)
            us[0] = first
        }
        if var last = us.last, let w = last.words.last {
            let text = String(w.text.reversed().drop { $0.isWhitespace }.reversed())
            last.words[last.words.count - 1] = SyncedLyricWord(text: text, startMs: w.startMs, durationMs: w.durationMs)
            us[us.count - 1] = last
        }
        return us
    }

    /// 一个词按字切开,时间按字数平分。字与字之间能不能断照 `cutPenalty`:拉丁 / 谚文字母之间只有硬切,
    /// 词里自带的空白、标点、连字符和中日韩字之间照常能断(整句只标成一个词时,词就是整句)。
    private static func exploded(_ word: SyncedLyricWord, measure: (String) -> CGFloat) -> [Unit] {
        let chars = Array(word.text)
        guard chars.count > 1 else {
            return [Unit(words: [word], width: measure(word.text))]
        }
        return chars.indices.map { k in
            let start = word.startMs + word.durationMs * k / chars.count
            let end = word.startMs + word.durationMs * (k + 1) / chars.count
            let text = String(chars[k])
            return Unit(words: [SyncedLyricWord(text: text, startMs: start, durationMs: end - start)],
                        width: measure(text))
        }
    }

    /// 逐行歌词没有词级时间，按文字宽度比例估算各段的起点。
    static func estimatedWords(_ line: Line, measure: (String) -> CGFloat) -> [SyncedLyricWord] {
        let tokens = textTokens(line.text)
        guard !tokens.isEmpty else { return [] }
        var end = line.sungEndMs ?? line.nextStartMs ?? (line.startMs + estimatedMaxMsPerToken * tokens.count)
        end = min(end, line.startMs + estimatedMaxMsPerToken * tokens.count)
        let span = max(tokens.count, end - line.startMs)
        let widths = tokens.map { max(measure($0), 0.01) }
        let total = widths.reduce(0, +)
        var acc: CGFloat = 0
        var out: [SyncedLyricWord] = []
        for (k, t) in tokens.enumerated() {
            let start = line.startMs + Int((CGFloat(span) * acc / total).rounded(.down))
            acc += widths[k]
            let stop = line.startMs + Int((CGFloat(span) * acc / total).rounded(.down))
            out.append(SyncedLyricWord(text: t, startMs: start, durationMs: max(1, stop - start)))
        }
        return out
    }

    /// 把一段文字切成词:连续的非空白、非中日韩字符是一个词(带上后面的空白),中日韩字一个字一个。
    static func textTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var buf = ""
        var bufEndsWithSpace = false
        var bufEndsWithCJK = false
        for ch in text {
            if ch.isWhitespace {
                buf.append(ch)
                bufEndsWithSpace = true
                continue
            }
            let cjk = ch.unicodeScalars.first.map(isCJK) ?? false
            if !buf.isEmpty && (cjk || bufEndsWithSpace || bufEndsWithCJK) {
                tokens.append(buf)
                buf = ""
            }
            buf.append(ch)
            bufEndsWithSpace = false
            bufEndsWithCJK = cjk
        }
        if !buf.isEmpty { tokens.append(buf) }
        return tokens
    }

    /// 主行拆成 parts 段时,译文那一行跟着切:切成放得下的最少段数(不超过 parts),按顺序摊到主行的
    /// 各段上(段数少于 parts 时相邻几段显示同一截)。切不出来返回 nil。
    /// `wordBreaks`:这行文字的词界(`WordBreaks`,中日文才有),一次拆分里算一次传下来。
    static func spreadText(_ text: String, parts: Int, row: LineLayoutBudget.Row, maxWidth: CGFloat,
                           wordBreaks: WordBreaks?) -> [String]? {
        for q in 2...max(2, parts) where q <= parts {
            guard let pieces = splitText(text, parts: q, row: row, maxWidth: maxWidth, wordBreaks: wordBreaks) else { continue }
            return (0..<parts).map { pieces[$0 * q / parts] }
        }
        return nil
    }

    /// 逐行装满:每段装到放不下为止,断在这一段里最后一个能断的地方(没有就硬断)。返回每段起点;有一个单位
    /// 自己就放不下返回 nil。
    static func packedCuts(widths: [CGFloat], trailing: [CGFloat], penalties: [CGFloat?],
                           maxWidth: CGFloat) -> [Int]? {
        let n = widths.count
        var prefix = [CGFloat](repeating: 0, count: n + 1)
        for k in 0..<n { prefix[k + 1] = prefix[k] + widths[k] }
        func partWidth(_ a: Int, _ c: Int) -> CGFloat { prefix[c] - prefix[a] - trailing[c - 1] }
        var starts = [0]
        var a = 0
        while a < n {
            guard partWidth(a, a + 1) <= maxWidth + fitTolerance else { return nil }
            var c = a + 1
            while c < n, partWidth(a, c + 1) <= maxWidth + fitTolerance { c += 1 }
            if c == n { break }
            var cut = c
            while cut > a + 1, penalties[cut] == nil { cut -= 1 }
            if penalties[cut] == nil { cut = c }
            starts.append(cut)
            a = cut
        }
        return starts
    }

    /// 译文逐行装满(主行也是逐行装满的时候用),段数不超过 parts,按顺序摊到主行各段上。
    static func packText(_ text: String, parts: Int, row: LineLayoutBudget.Row, maxWidth: CGFloat,
                         wordBreaks: WordBreaks?) -> [String]? {
        let tokens = textTokens(text).flatMap { t -> [String] in
            row.measure(t) > maxWidth + fitTolerance ? t.map(String.init) : [t]
        }
        guard !tokens.isEmpty else { return nil }
        let spaceWidth = row.measure(" ")
        let widths = tokens.map(row.measure)
        let trailing = tokens.map { $0.last?.isWhitespace == true ? spaceWidth : 0 }
        let penalties = cutPenalties(tokens, wordBreaks: wordBreaks)
        guard let starts = packedCuts(widths: widths, trailing: trailing, penalties: penalties, maxWidth: maxWidth),
              starts.count <= parts else { return nil }
        let q = starts.count
        let pieces = starts.indices.map { i -> String in
            let end = i + 1 < q ? starts[i + 1] : tokens.count
            return tokens[starts[i]..<end].joined().trimmingCharacters(in: .whitespaces)
        }
        guard pieces.allSatisfy({ row.measure($0) <= maxWidth + fitTolerance }) else { return nil }
        return (0..<parts).map { pieces[$0 * q / parts] }
    }

    /// 没有时间的一行文字(译文)切成 parts 段、每段都放得下;切不出来返回 nil。
    static func splitText(_ text: String, parts: Int, row: LineLayoutBudget.Row, maxWidth: CGFloat,
                          wordBreaks: WordBreaks?) -> [String]? {
        var tokens = textTokens(text)
        var glued = [Bool](repeating: false, count: tokens.count)
        // 一个词比整行还宽就按字切开,切口只在别处断不开时用。
        var k = 0
        while k < tokens.count {
            if row.measure(tokens[k]) > maxWidth + fitTolerance, tokens[k].count > 1 {
                let chars = tokens[k].map(String.init)
                tokens.replaceSubrange(k...k, with: chars)
                glued.replaceSubrange(k...k, with: [false] + [Bool](repeating: true, count: chars.count - 1))
                k += chars.count
            } else {
                k += 1
            }
        }
        guard tokens.count >= parts else { return nil }
        let spaceWidth = row.measure(" ")
        let widths = tokens.map(row.measure)
        let trailing = tokens.map { $0.last?.isWhitespace == true ? spaceWidth : 0 }
        let refined = cutPenalties(tokens, wordBreaks: wordBreaks)
        let natural: [CGFloat?] = tokens.indices.map { c in glued[c] ? nil : refined[c] }
        let forced: [CGFloat?] = tokens.indices.map { c in c == 0 ? nil : (natural[c] ?? 1) }
        for penalties in [natural, forced] {
            guard let starts = balancedCuts(widths: widths, trailing: trailing, penalties: penalties,
                                            parts: parts, maxWidth: maxWidth) else { continue }
            let out = starts.indices.map { i -> String in
                let end = i + 1 < starts.count ? starts[i + 1] : tokens.count
                return tokens[starts[i]..<end].joined().trimmingCharacters(in: .whitespaces)
            }
            if out.allSatisfy({ row.measure($0) <= maxWidth + fitTolerance }) { return out }
        }
        return nil
    }

    /// 把 n 个单位切成 parts 段、每段宽不超过 maxWidth:各段宽度越接近越好,断点代价(`penalties[c]` = 在第 c 个
    /// 单位前面断,nil = 不能断)越小越好。返回每段从第几个单位开始(第一个恒为 0);切不出来返回 nil。
    static func balancedCuts(widths: [CGFloat], trailing: [CGFloat], penalties: [CGFloat?],
                             parts: Int, maxWidth: CGFloat) -> [Int]? {
        let n = widths.count
        guard parts >= 1, parts <= n else { return nil }
        var prefix = [CGFloat](repeating: 0, count: n + 1)
        for k in 0..<n { prefix[k + 1] = prefix[k] + widths[k] }
        func partWidth(_ a: Int, _ c: Int) -> CGFloat { prefix[c] - prefix[a] - trailing[c - 1] }
        let target = partWidth(0, n) / CGFloat(parts)
        let scale = max(maxWidth, 1)
        let inf = CGFloat.infinity
        var cost = [[CGFloat]](repeating: [CGFloat](repeating: inf, count: n + 1), count: parts + 1)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: n + 1), count: parts + 1)
        cost[0][0] = 0
        for k in 1...parts {
            // 前 c 个单位切成 k 段:c 至少 k 个,后面还得留够 parts - k 段各一个。
            for c in k...(n - (parts - k)) {
                // 从 c 往前找这一段的起点:越往前越宽,超宽就不用再往前了。
                for a in stride(from: c - 1, through: k - 1, by: -1) {
                    let w = partWidth(a, c)
                    guard w <= maxWidth + fitTolerance else { break }
                    let prev = cost[k - 1][a]
                    guard prev.isFinite else { continue }
                    var p: CGFloat = 0
                    if a > 0 {
                        guard let pen = penalties[a] else { continue }
                        p = pen
                    }
                    let d = (w - target) / scale
                    let total = prev + d * d + p
                    if total < cost[k][c] {
                        cost[k][c] = total
                        parent[k][c] = a
                    }
                }
            }
        }
        guard cost[parts][n].isFinite else { return nil }
        var starts: [Int] = []
        var c = n
        for k in stride(from: parts, through: 1, by: -1) {
            let a = parent[k][c]
            starts.append(a)
            c = a
        }
        return starts.reversed()
    }

    /// 一串单位里每个单位前面断开的代价(第 0 个恒为 nil):`cutPenalty`,中日文字与字之间再按 `wordBreaks` 细分。
    /// 主行与译文共用这套切分规则。
    static func cutPenalties(_ texts: [String], wordBreaks: WordBreaks?) -> [CGFloat?] {
        var out: [CGFloat?] = []
        var offset = 0
        for (c, text) in texts.enumerated() {
            if c > 0 {
                let base = cutPenalty(after: texts[c - 1], before: text)
                if base == cjkCutPenalty, let wordBreaks {
                    out.append(wordBreaks.penalty(at: offset))
                } else {
                    out.append(base)
                }
            } else {
                out.append(nil)
            }
            offset += text.utf16.count
        }
        return out
    }

    /// 在两个词之间断开的代价;nil = 不能断(拉丁词、谚文词中间,下一段会以标点或行首禁则字开头,上一段会以
    /// 左括号 / 左引号结尾,促音后面)。
    public static func cutPenalty(after previous: String, before next: String) -> CGFloat? {
        guard let last = previous.unicodeScalars.last, let first = next.unicodeScalars.first else { return 0 }
        // 禁则:标点、小假名、长音、右括号 / 右引号这些不放到下一段开头,左括号 / 左引号不留在上一段末尾。
        if sentencePunctuation.contains(first) || noLineStart.contains(first) { return nil }
        let visibleLast = previous.unicodeScalars.last { !CharacterSet.whitespacesAndNewlines.contains($0) }
        if let v = visibleLast, noLineEnd.contains(v) { return nil }
        // 标点、右括号后面能断。
        if let v = visibleLast, sentencePunctuation.contains(v) || closingBrackets.contains(v) { return 0 }
        if CharacterSet.whitespacesAndNewlines.contains(last) || CharacterSet.whitespacesAndNewlines.contains(first) {
            return 0.05
        }
        // 促音和后面的假名放在同一段。
        if last == "っ" || last == "ッ" { return nil }
        if last == "-", CharacterSet.alphanumerics.contains(first) { return 0.1 }
        if isHangul(last) && isHangul(first) { return nil }
        if isCJK(last) || isCJK(first) { return cjkCutPenalty }
        return nil
    }

    /// 中日文字与字之间(不隔空格、标点)断开的代价。拆长句时中日文行再按分词器的词界细分(`WordBreaks`)。
    static let cjkCutPenalty: CGFloat = 0.15

    static let sentencePunctuation = CharacterSet(charactersIn: ",.!?;:、，。！？；：…")

    /// 右括号。后面能断(同标点);右引号不算,它在拉丁文字里也当撇号用(「don’t」)。
    static let closingBrackets = CharacterSet(charactersIn: ")）]］}｝」』】〕〉》〗〙〛｣")

    public static let noLineStart = closingBrackets.union(CharacterSet(charactersIn:
        "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿｧｨｩｪｫｬｭｮｯ"
            + "ーｰ々〻ゝゞヽヾ〜～・･‥．｡､”’"))

    /// 不留在一段末尾的字(禁则):左括号 / 左引号。
    public static let noLineEnd = CharacterSet(charactersIn: "(（[［{｛「『【〔〈《〖〘〚｢“‘")

    /// 一行中日文按分词器切出的词界:词中间不断(只在硬切时用),切在助词 / 助动词前面会拆开一个短语、代价高,
    /// 切在日文助词或助动词后面的代价较低，因为那里往往是短语边界。
    public struct WordBreaks {
        /// 落在一个词中间的 UTF-16 下标。
        let inside: Set<Int>
        /// 词界上不同于 `cjkCutPenalty` 的代价,按 UTF-16 下标。
        let penalties: [Int: CGFloat]

        static let beforeAttached: CGFloat = 0.3
        static let afterAttached: CGFloat = 0.1

        /// 日文的助词、助动词:分词器把它们切成单独的词,跟前面的词合起来才是一个短语。
        static let japaneseAttached: Set<String> = [
            "は", "が", "を", "に", "へ", "と", "で", "も", "の", "や", "か", "な", "ね", "よ", "ぞ", "ぜ", "さ", "わ",
            "ば", "て", "って", "から", "まで", "より", "けど", "けれど", "ので", "のに", "し", "ながら", "たり",
            "たら", "だら", "なら",
            "だけ", "しか", "ほど", "くらい", "ぐらい", "など", "なんて",
            "た", "だ", "たい", "ない", "ます", "です", "う", "よう", "れる", "られる", "せる", "させる",
            "れ", "られ", "せ", "させ", "ませ", "まし", "でし", "なかっ", "たかっ", "だっ", "ちゃ", "じゃ",
            "てる", "でる", "ちゃう", "ちゃっ", "じゃう", "じゃっ",
            "ん", "ぬ", "ず", "だろう", "でしょう", "らしい", "みたい",
        ]
        /// 日文一句以这些词开头时,它是接着上一句的(合并时连写,见 `mergeSeparator`)。是 `japaneseAttached` 里
        /// 不会出现在句首的那些:去掉了也能开一句新话的「だ(だから / だけど)」「で(でも)」「ない」「なんて」「けど」
        /// 「よう(ようこそ)」「さ」「なら」「だっ(だって)」这类。
        static let japaneseContinuationStarts: Set<String> = [
            "の", "を", "が", "は", "に", "へ", "と", "も", "や", "か", "ね", "よ", "ぞ", "ぜ", "ば", "て", "って", "しか",
            "た", "たい", "ます", "です", "れる", "られる", "せる", "させる", "ん", "ぬ", "ず", "まし", "でし", "ませ",
            "なかっ", "たかっ", "てる", "でる", "ちゃう", "ちゃっ", "じゃう", "じゃっ", "らしい", "みたい", "たら", "だら",
        ]
        /// `japaneseContinuationStarts` 里各词的头一个字:后一句不以这些字开头就不用分词。
        static let japaneseContinuationInitials: Set<Character> = Set(japaneseContinuationStarts.compactMap(\.first))
        /// 中文里跟着前一个词的虚字:不放到下一段开头。
        static let chineseAttached: Set<String> = [
            "的", "地", "得", "了", "着", "过", "吗", "呢", "吧", "啊", "呀", "们", "么", "嘛", "啦", "哦", "喔",
        ]

        public init?(text: String, script: LyricScript) {
            let ns = text as NSString
            let pool: StringTokenizerPool
            switch script {
            case .japanese: pool = Self.japaneseTokenizers
            case .chinese: pool = Self.chineseTokenizers
            default: return nil
            }
            let found = pool.withTokenizer(for: text as CFString) { tokenizer -> [(start: Int, end: Int, text: String)]? in
                var pieces: [(start: Int, end: Int, text: String)] = []
                while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
                    let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                    let piece = ns.substring(with: NSRange(location: r.location, length: r.length))
                    guard !piece.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    pieces.append((r.location, r.location + r.length, piece))
                }
                return pieces
            }
            guard let pieces = found, !pieces.isEmpty else { return nil }
            let attached = script == .japanese ? Self.japaneseAttached : Self.chineseAttached
            var inside = Set<Int>()
            var penalties: [Int: CGFloat] = [:]
            for (k, p) in pieces.enumerated() {
                if p.end - p.start > 1 { inside.formUnion((p.start + 1)..<p.end) }
                guard k > 0, pieces[k - 1].end == p.start else { continue }
                if attached.contains(p.text) {
                    penalties[p.start] = Self.beforeAttached
                } else if script == .japanese, attached.contains(pieces[k - 1].text) {
                    penalties[p.start] = Self.afterAttached
                }
            }
            if script == .japanese {
                // 一长串片假名被分词器认成一个词时(「プリーズプリーズヘルプミー」),连续重复的那几段之间能断。
                for p in pieces where p.end - p.start >= 4
                    && p.text.unicodeScalars.allSatisfy({ (0x30A1...0x30FA).contains($0.value) || $0 == "ー" }) {
                    for cut in Self.repeatBoundaries(p.text) { inside.remove(p.start + cut) }
                }
            }
            self.inside = inside
            self.penalties = penalties
        }

        /// 一段文字里连续重复的片段(至少 2 个字)每一遍前后的下标(UTF-16)。重复从它能往左延伸到的最早位置算起:
        /// 错开一位的同一段重复不算,不然一段周期重复里每个位置都成了断点。
        static func repeatBoundaries(_ text: String) -> Set<Int> {
            let u = Array(text.utf16)
            var out = Set<Int>()
            guard u.count >= 4 else { return out }
            for length in 2...(u.count / 2) {
                for start in 0...(u.count - 2 * length)
                where (start == 0 || u[start - 1] != u[start - 1 + length])
                    && u[start..<(start + length)] == u[(start + length)..<(start + 2 * length)] {
                    if start > 0 { out.insert(start) }
                    var k = start + length
                    while k + length <= u.count, u[(k - length)..<k] == u[k..<(k + length)] {
                        out.insert(k)
                        k += length
                    }
                    if k < u.count { out.insert(k) }
                }
            }
            return out
        }

        /// 日文一段文字分词后的第一个词(跳过空白)。
        static func firstJapaneseToken(_ text: String) -> String? {
            japaneseTokenizers.withTokenizer(for: text as CFString) { tokenizer -> String? in
                while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
                    let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                    let piece = (text as NSString).substring(with: NSRange(location: r.location, length: r.length))
                    if !piece.trimmingCharacters(in: .whitespaces).isEmpty { return piece }
                }
                return nil
            }
        }

        /// 在 UTF-16 下标 `offset` 处断开的代价;nil = 落在一个词中间。
        public func penalty(at offset: Int) -> CGFloat? {
            inside.contains(offset) ? nil : penalties[offset] ?? LyricsSegmenter.cjkCutPenalty
        }

        private static let japaneseLocale = Locale(identifier: "ja") as CFLocale
        private static let chineseLocale = Locale(identifier: "zh") as CFLocale
        private static let japaneseTokenizers = StringTokenizerPool(unit: kCFStringTokenizerUnitWordBoundary, locale: japaneseLocale)
        private static let chineseTokenizers = StringTokenizerPool(unit: kCFStringTokenizerUnitWord, locale: chineseLocale)
    }

    static func isHangul(_ scalar: Unicode.Scalar) -> Bool { (0xAC00...0xD7AF).contains(scalar.value) }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x3040...0x30FF).contains(v) || (0x3400...0x9FFF).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0xAC00...0xD7AF).contains(v)
    }

    /// 字数:汉字 / 谚文一个字算 1,假名算半个,其余按空白分开的词算 1(只算带字母或数字的词);片假名中点「・」不算。
    /// 判「很短的一句」用。
    public static func displayWidth(_ text: String) -> Double {
        var width = 0.0
        var inWord = false
        var wordHasAlnum = false
        for scalar in text.unicodeScalars {
            let separator = scalar == "・"
            let cjk = isCJK(scalar) && !separator
            if cjk || separator || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if inWord, wordHasAlnum { width += 1 }
                inWord = false
                wordHasAlnum = false
                if cjk { width += (0x3040...0x30FF).contains(scalar.value) ? 0.5 : 1 }
                continue
            }
            inWord = true
            if CharacterSet.alphanumerics.contains(scalar) { wordHasAlnum = true }
        }
        if inWord, wordHasAlnum { width += 1 }
        return width
    }
}
