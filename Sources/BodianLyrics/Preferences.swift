import AppKit
import SwiftUI

enum AlignmentChoice: String, Codable, CaseIterable {
    case leading, center, trailing

    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
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

enum SecondaryLine: String, Codable, CaseIterable {
    case nextLine, translation, inlineTranslation, off
}

enum MenuContent: String, Codable, CaseIterable {
    case lyrics, translation, title, titleArtist
}

enum IconPosition: String, Codable, CaseIterable {
    case leading, trailing, off
}

enum IconSize: String, Codable, CaseIterable {
    case small, standard, large

    var points: CGFloat {
        switch self {
        case .small: return 12
        case .standard: return 14
        case .large: return 17
        }
    }
}

enum IslandStyle: String, Codable, CaseIterable {
    case solidBlack, frostedGlass, darkGradient, coverArt
}

enum EarContent: String, Codable, CaseIterable {
    case none, artwork, title, artist, album, elapsed, remaining, player
}

enum Side: String, Codable, CaseIterable {
    case left, right
}

enum ProgressStyle: String, Codable, CaseIterable {
    case off, ears, bottom
}

enum IslandColor: String, Codable, CaseIterable {
    case accent, rainbow
}

struct Preferences: Codable, Equatable {
    var language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    var followLaunch = true
    var followQuit = true
    var splitLongLines = false
    var mergeShortLines = false
    var offsets: [String: Int] = [:]

    var menuEnabled = true
    var menuWidth = 250.0
    var menuMaxCharacters = 60
    var menuFixedWidth = false
    var menuAlignment = AlignmentChoice.leading
    var menuKaraoke = true
    var menuTextColor = ""
    var menuFillColor = ""
    var menuRainbow = false
    var menuIconPosition = IconPosition.leading
    var menuCentered = false
    var menuScreen = ""
    var menuFontFamily = ""
    var menuFontWeight = WeightChoice.regular
    var menuFontSize = 0.0
    var menuSecondary = SecondaryLine.nextLine
    var menuTitleWithoutLyrics = true
    var menuContent = MenuContent.lyrics
    var menuIconAnimates = true
    var menuIconSize = IconSize.standard

    var islandEnabled = true
    var islandKaraoke = true
    var islandHideFullScreen = true
    var islandShowLyrics = true
    var islandEqualizer = true
    var islandExpandedNextLine = true
    var islandExpandedLyricList = true
    var islandExpandedOffset = true
    var islandExpandedTitle = true
    var islandExpandedArtist = true
    var islandExpandedAlbum = true
    var islandTrackDrop = true
    var islandGestures = true
    var islandProgress = ProgressStyle.ears
    var islandHideInCapture = false
    var islandHideWhenPaused = false
    var islandLockScreen = false
    var islandCollapseWithoutLyrics = false
    var islandFadeOnHover = false
    var islandAllScreens = false
    var islandFollowActive = false
    var islandCollapseWhenPaused = false
    var islandExpandedArtwork = false
    var islandLyricArtwork = false
    var islandStyle = IslandStyle.coverArt
    var islandExpandedStyle: IslandStyle?
    var islandEqualizerSide = Side.right
    var islandListLines = 5
    var islandLyricArtworkSide = Side.right
    var islandAlignment: AlignmentChoice?
    var islandColor = IslandColor.accent
    var islandSecondary = SecondaryLine.nextLine
    var islandFontFamily = ""
    var islandFontWeight = WeightChoice.semibold
    var islandFontSize = 13.0
    var islandRowHeight = 26.0
    var islandLeftEar = EarContent.artwork
    var islandRightEar = EarContent.none
    var islandScreen = ""
    var islandWidth = 252.0
    var islandExpandedWidth = 482.0
    var islandCorner = -1.0
    var islandExpandedCorner = -1.0

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
