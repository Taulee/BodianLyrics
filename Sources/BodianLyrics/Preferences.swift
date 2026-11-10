import AppKit
import SwiftUI

enum AlignmentChoice: String, Codable {
    case center, trailing

    var alignment: Alignment { self == .center ? .center : .trailing }
}

enum WeightChoice: String, Codable, CaseIterable {
    case regular, medium, semibold, bold

    var weight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

enum LyricOffsetAction: Int, CaseIterable {
    case earlier = 100
    case later = -100
    case reset = 0

    func applying(to offset: Int) -> Int {
        self == .reset ? 0 : offset + rawValue
    }

    func title(_ preferences: Preferences) -> String {
        switch self {
        case .earlier: return preferences.label("提前 100 毫秒", "Earlier by 100 ms")
        case .later: return preferences.label("延后 100 毫秒", "Later by 100 ms")
        case .reset: return preferences.label("重置", "Reset")
        }
    }
}

struct MenuPosition: Codable, Equatable {
    static let horizontalLimit = 6
    static let verticalLimit = 4

    var x = 0
    var y = 0
}

struct Preferences: Codable, Equatable {
    static let menuBarFontSize = Double(NSFont.menuBarFont(ofSize: 0).pointSize)

    var language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    var followLaunch = true
    var followQuit = true
    var splitLongLines = false
    var mergeShortLines = false
    var offsets: [String: Int] = [:]
    var globalLyricOffset: Int?

    var menuWidth = 250.0
    var menuMaxCharacters = 60
    var menuFixedWidth = false
    var menuAlignment = AlignmentChoice.center
    var menuKaraoke = true
    var menuTextColor = ""
    var menuFillColor = ""
    var menuFontFamily = ""
    var menuFontWeight = WeightChoice.regular
    var menuFontSize = Self.menuBarFontSize
    var menuPosition: MenuPosition?

    var menuFont: NSFont {
        if menuFontSize == Self.menuBarFontSize, menuFontFamily.isEmpty, menuFontWeight == .regular {
            return NSFont.menuBarFont(ofSize: 0)
        }
        return lyricFont(family: menuFontFamily, size: menuFontSize, weight: menuFontWeight.weight)
    }

    func offsetLabel(_ offset: Int) -> String {
        let signed = offset > 0 ? "+\(offset)" : String(offset)
        return label("\(signed) 毫秒", "\(signed) ms")
    }

    func label(_ chinese: String, _ english: String) -> String {
        language == "zh-Hans" ? chinese : english
    }
}

func lyricFont(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let standard = NSFont.systemFont(ofSize: size, weight: weight)
    if family.isEmpty { return standard }
    return NSFontManager.shared.font(withFamily: family, traits: [], weight: Int(5 + weight.rawValue * 10), size: size) ?? standard
}

func textWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}

func rgbHex(_ color: Color) -> String {
    let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
    return String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
}

func hexColor(_ hex: String) -> Color? {
    guard let value = UInt32(hex, radix: 16) else { return nil }
    return Color(red: Double(value >> 16 & 255) / 255,
                 green: Double(value >> 8 & 255) / 255,
                 blue: Double(value & 255) / 255)
}
