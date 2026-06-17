//
//  BookSettings.swift
//  readBook
//
//  全局阅读外观设置及其相关枚举（主题 / 字体 / 翻页动画）。
//  主题色集中在此作为设计令牌，禁止在视图层散落硬编码色值。
//

import SwiftUI

/// 阅读主题。`light` 跟随浅色，`night` 为暗黑，`paper`/`eyeGreen` 为护眼主题。
enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case light
    case night
    case paper      // 羊皮纸
    case eyeGreen   // 豆沙绿

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: "默认"
        case .night: "夜间"
        case .paper: "羊皮纸"
        case .eyeGreen: "豆沙绿"
        }
    }

    /// 背景色（设计令牌）。
    var backgroundColor: Color {
        switch self {
        case .light: Color(red: 0.98, green: 0.98, blue: 0.98)
        case .night: Color(red: 0.11, green: 0.11, blue: 0.12)
        case .paper: Color(red: 0.96, green: 0.91, blue: 0.80)
        case .eyeGreen: Color(red: 0.78, green: 0.86, blue: 0.74)
        }
    }

    /// 正文文字色（设计令牌）。
    var textColor: Color {
        switch self {
        case .light: Color(red: 0.13, green: 0.13, blue: 0.14)
        case .night: Color(red: 0.78, green: 0.78, blue: 0.80)
        case .paper: Color(red: 0.30, green: 0.22, blue: 0.12)
        case .eyeGreen: Color(red: 0.18, green: 0.25, blue: 0.16)
        }
    }

    /// 次要文字色（章节名 / 进度等）。
    var secondaryTextColor: Color { textColor.opacity(0.6) }

    var isDark: Bool { self == .night }
}

/// 阅读字体选择。
enum ReaderFont: String, Codable, CaseIterable, Identifiable {
    case system
    case songti  // 宋体
    case kaiti   // 楷体

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "系统"
        case .songti: "宋体"
        case .kaiti: "楷体"
        }
    }

    /// 对应的 UIFont 字体名（nil 表示系统字体）。
    var fontName: String? {
        switch self {
        case .system: nil
        case .songti: "STSong"
        case .kaiti: "STKaiti"
        }
    }
}

/// 翻页动画。
enum PageAnimation: String, Codable, CaseIterable, Identifiable {
    case curl   // 卷页
    case slide  // 滑动
    case none   // 无动画

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curl: "卷页"
        case .slide: "滑动"
        case .none: "无"
        }
    }
}

/// 阅读模式：翻页 / 连续滚动。
enum ReadingMode: String, Codable, CaseIterable, Identifiable {
    case paged
    case scroll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paged: "翻页"
        case .scroll: "滚动"
        }
    }
}

/// 全局阅读设置。所有数值字段在解码时做边界与缺失防御。
struct ReaderSettings: Codable, Equatable {
    static let minFontSize: Double = 16
    static let maxFontSize: Double = 32

    var fontSize: Double
    var lineSpacing: Double
    var theme: ReaderTheme
    /// 主题是否跟随系统：开启时浅色用 light、深色用 night，忽略手动 theme。
    var followSystem: Bool
    var font: ReaderFont
    var pageAnimation: PageAnimation
    var readingMode: ReadingMode
    /// 应用内亮度（0.2–1.0，直接映射到系统屏幕亮度）。
    var brightness: Double

    static let `default` = ReaderSettings(
        fontSize: 20,
        lineSpacing: 8,
        theme: .paper,
        followSystem: false,
        font: .system,
        pageAnimation: .none,
        readingMode: .paged,
        brightness: 0.8
    )

    init(
        fontSize: Double,
        lineSpacing: Double,
        theme: ReaderTheme,
        followSystem: Bool,
        font: ReaderFont,
        pageAnimation: PageAnimation,
        readingMode: ReadingMode,
        brightness: Double
    ) {
        self.fontSize = fontSize.clamped(to: Self.minFontSize...Self.maxFontSize)
        self.lineSpacing = max(0, lineSpacing)
        self.theme = theme
        self.followSystem = followSystem
        self.font = font
        self.pageAnimation = pageAnimation
        self.readingMode = readingMode
        self.brightness = brightness.clamped(to: 0.2...1.0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderSettings.default
        let rawSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? d.fontSize
        fontSize = rawSize.clamped(to: Self.minFontSize...Self.maxFontSize)
        lineSpacing = max(0, (try? c.decodeIfPresent(Double.self, forKey: .lineSpacing)) ?? d.lineSpacing)
        theme = (try? c.decodeIfPresent(ReaderTheme.self, forKey: .theme)) ?? d.theme
        followSystem = (try? c.decodeIfPresent(Bool.self, forKey: .followSystem)) ?? d.followSystem
        font = (try? c.decodeIfPresent(ReaderFont.self, forKey: .font)) ?? d.font
        pageAnimation = (try? c.decodeIfPresent(PageAnimation.self, forKey: .pageAnimation)) ?? d.pageAnimation
        readingMode = (try? c.decodeIfPresent(ReadingMode.self, forKey: .readingMode)) ?? d.readingMode
        let rawBrightness = (try? c.decodeIfPresent(Double.self, forKey: .brightness)) ?? d.brightness
        brightness = rawBrightness.clamped(to: 0.2...1.0)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
