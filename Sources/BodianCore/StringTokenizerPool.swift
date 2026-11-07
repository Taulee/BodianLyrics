import Foundation

/// 同一种语言、同一种切法的系统分词器,借出去用、用完收回。新建一个分词器要加载词典,比切一行歌词贵得多。
///
/// 一个分词器一次只处理一段文字，归还时清空上次的内容。
final class StringTokenizerPool: @unchecked Sendable {
    private let unit: CFOptionFlags
    private let locale: CFLocale?
    private let lock = NSLock()
    private var idle: [CFStringTokenizer] = []
    private static let maxIdle = 4

    init(unit: CFOptionFlags, locale: CFLocale?) {
        self.unit = unit
        self.locale = locale
    }

    /// 拿一个切 `text` 的分词器跑 `body`;建不出分词器时返回 nil。分词器只在 `body` 里能用。
    func withTokenizer<T>(for text: CFString, _ body: (CFStringTokenizer) -> T?) -> T? {
        let range = CFRangeMake(0, CFStringGetLength(text))
        lock.lock()
        let reused = idle.popLast()
        lock.unlock()
        let tokenizer: CFStringTokenizer
        if let reused {
            CFStringTokenizerSetString(reused, text, range)
            tokenizer = reused
        } else if let created = CFStringTokenizerCreate(nil, text, range, unit, locale) {
            tokenizer = created
        } else {
            return nil
        }
        defer {
            CFStringTokenizerSetString(tokenizer, "" as CFString, CFRangeMake(0, 0))
            lock.lock()
            if idle.count < Self.maxIdle { idle.append(tokenizer) }
            lock.unlock()
        }
        return body(tokenizer)
    }
}
