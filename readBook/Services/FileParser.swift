//
//  FileParser.swift
//  readBook
//
//  TXT 文件解析：编码检测（BOM → UTF-8 → GB18030）、可读性校验、章节结构识别。
//

import Foundation

enum FileParserError: LocalizedError {
    case unreadable
    case unsupportedEncoding
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取文件内容"
        case .unsupportedEncoding: "文件编码无法识别，暂不支持"
        case .empty: "文件内容为空"
        }
    }
}

/// 解析结果：标准化后的全文 + 章节索引。
struct ParsedBook {
    var title: String
    var fullText: String
    var chapters: [Chapter]
}

enum FileParser {

    /// 从原始数据解析为书籍。fileName 用于回退书名。
    static func parse(data: Data, fileName: String) throws -> ParsedBook {
        let raw = try decode(data: data)
        let text = normalize(raw)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileParserError.empty
        }
        let chapters = detectChapters(in: text)
        let title = (fileName as NSString).deletingPathExtension
        return ParsedBook(title: title.isEmpty ? "未命名书籍" : title, fullText: text, chapters: chapters)
    }

    // MARK: - 编码检测

    /// 顺序：BOM → UTF-8 严格 → GB18030（GBK/GB2312 超集）。失败抛错。
    static func decode(data: Data) throws -> String {
        guard !data.isEmpty else { throw FileParserError.empty }

        if let bomDecoded = decodeWithBOM(data) {
            return bomDecoded
        }
        if let utf8 = String(data: data, encoding: .utf8), isReadable(utf8) {
            return utf8
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let gb = String(data: data, encoding: String.Encoding(rawValue: gb18030)), isReadable(gb) {
            return gb
        }
        // 最后兜底尝试 UTF-8（允许少量替换字符）
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        throw FileParserError.unsupportedEncoding
    }

    private static func decodeWithBOM(_ data: Data) -> String? {
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        return nil
    }

    /// 可读性校验：替换字符（U+FFFD）占比过高则判定为乱码。
    private static func isReadable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let sampleCount = min(text.count, 2000)
        let sample = text.prefix(sampleCount)
        let badCount = sample.reduce(0) { $0 + ($1 == "\u{FFFD}" ? 1 : 0) }
        return Double(badCount) / Double(sampleCount) < 0.01
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - 章节识别

    private static let chapterPatterns: [String] = [
        #"^\s*第\s*[零一二三四五六七八九十百千万0-9]+\s*[章卷回节篇](?:[ 　:：、.\-—].*)?$"#,
        #"^\s*Chapter\s+\d+.*$"#,
        #"^\s*\d{1,4}\s*[、.．]?\s*.{0,30}$"#
    ]

    /// 按行扫描识别章节边界。零命中时全文作为单一章节；相邻过近的标题去重。
    static func detectChapters(in text: String) -> [Chapter] {
        let ns = text as NSString
        let fullLength = ns.length
        let regexes = chapterPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines])
        }

        var boundaries: [(offset: Int, title: String)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: fullLength), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 40 else { return }
            let lineNSRange = NSRange(location: 0, length: (line as NSString).length)
            for regex in regexes where regex.firstMatch(in: line, options: [], range: lineNSRange) != nil {
                boundaries.append((lineRange.location, trimmed))
                break
            }
        }

        // 相邻标题去重：间隔字符数过小（疑似误匹配/空章节）则丢弃后者。
        var deduped: [(offset: Int, title: String)] = []
        for b in boundaries {
            if let last = deduped.last, b.offset - last.offset < 20 { continue }
            deduped.append(b)
        }

        guard !deduped.isEmpty else {
            return [Chapter(index: 0, title: "正文", startOffset: 0, length: fullLength)]
        }

        // 首个章节之前若有正文（如序言），并入第一章之前作为"前言"章节。
        var chapters: [Chapter] = []
        var startIndex = 0
        if deduped[0].offset > 0 {
            chapters.append(Chapter(index: 0, title: "前言", startOffset: 0, length: deduped[0].offset))
            startIndex = 1
        }
        for (i, b) in deduped.enumerated() {
            let end = (i + 1 < deduped.count) ? deduped[i + 1].offset : fullLength
            chapters.append(Chapter(index: startIndex + i, title: b.title, startOffset: b.offset, length: end - b.offset))
        }
        return chapters
    }
}
