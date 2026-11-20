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

    /// 单章 UTF-16 长度达到该值就拆开。验收要求拆分后 length < 50_000，硬切因此落在 49_999。
    private static let maxChapterLength = 50_000

    private static let chapterPatterns: [String] = [
        // 章/卷允许标题紧贴，如「第1章都会说了」。回/节/篇仍要求分隔符或独占一行，避免「第一节课」误判。
        #"^\s*第\s*[零一二三四五六七八九十百千万0-9]+\s*[章卷](?:[ 　:：、.\-—]?.*)?$"#,
        #"^\s*第\s*[零一二三四五六七八九十百千万0-9]+\s*[回节篇](?:[ 　:：、.\-—].*)?$"#,
        #"^\s*Chapter\s+\d+.*$"#,
        #"^\s*\d{1,4}\s*[、.．]?\s*.{0,30}$"#,
        // 番外篇必须写在番外前面。标题后若还有字，必须先有空格、标点或编号，避免「尾声渐渐消失」误判。
        #"^\s*(?:番外篇|番外|序章|楔子|引子|后记|尾声|终章)(?:\s*[0-9零一二三四五六七八九十百千万]{1,8})?(?:[ 　.、:：\-—].*)?$"#,
    ]

    /// 按行扫描识别章节边界。零命中时全文作为「正文」；相邻过近的标题去重。
    /// 单章达到 `maxChapterLength` 时只扫描该章区间，按空行或硬切拆开。
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

        let rawChapters: [Chapter]
        if deduped.isEmpty {
            rawChapters = [Chapter(index: 0, title: "正文", startOffset: 0, length: fullLength)]
        } else {
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
            rawChapters = chapters
        }
        return limitChapterLength(rawChapters, in: ns)
    }

    /// 把超长章节拆成若干段。只采用窗口后半段的空行；没有合适空行则按完整字符硬切。
    private static func limitChapterLength(_ chapters: [Chapter], in text: NSString) -> [Chapter] {
        var expanded: [Chapter] = []
        expanded.reserveCapacity(chapters.count)
        for chapter in chapters {
            let slices = splitRange(start: chapter.startOffset, length: chapter.length, in: text)
            if slices.count <= 1 {
                expanded.append(chapter)
                continue
            }
            for (part, slice) in slices.enumerated() {
                let title = "\(chapter.title) (\(part + 1)/\(slices.count))"
                expanded.append(Chapter(index: 0, title: title, startOffset: slice.start, length: slice.length))
            }
        }
        return expanded.enumerated().map { index, chapter in
            Chapter(index: index, title: chapter.title, startOffset: chapter.startOffset, length: chapter.length)
        }
    }

    private struct TextSlice {
        var start: Int
        var length: Int
    }

    /// 只扫描 [start, start+length)。返回的切片首尾相接，长度之和等于原 length。
    private static func splitRange(start: Int, length: Int, in text: NSString) -> [TextSlice] {
        guard length >= maxChapterLength,
              start >= 0,
              start <= text.length,
              start + length <= text.length else {
            return [TextSlice(start: start, length: length)]
        }

        let pieceCap = maxChapterLength - 1
        var slices: [TextSlice] = []
        var offset = start
        let end = start + length
        while offset < end {
            let remaining = end - offset
            if remaining < maxChapterLength {
                slices.append(TextSlice(start: offset, length: remaining))
                break
            }
            let pieceLength = cutLength(in: text, start: offset, window: pieceCap)
            slices.append(TextSlice(start: offset, length: pieceLength))
            offset += pieceLength
        }
        return slices
    }

    /// 在窗口后半段取最靠近上限的 `\n\n`（切在空行之后）。太靠前的空行（常见于标题后）不用，改为硬切。
    private static func cutLength(in text: NSString, start: Int, window: Int) -> Int {
        guard window > 0 else { return 1 }
        let range = NSRange(location: start, length: window)
        let found = text.range(of: "\n\n", options: .backwards, range: range)
        if found.location != NSNotFound {
            let afterBlank = found.location + found.length - start
            if afterBlank >= window / 2, afterBlank <= window {
                return afterBlank
            }
        }
        return alignCutToCharacter(in: text, start: start, proposed: window)
    }

    /// 硬切点若落在代理对或组合字符中间，退回到该字符起点，避免切出 U+FFFD。
    private static func alignCutToCharacter(in text: NSString, start: Int, proposed: Int) -> Int {
        let boundary = start + proposed
        guard proposed > 0, boundary < text.length else { return max(proposed, 1) }
        let sequence = text.rangeOfComposedCharacterSequence(at: boundary)
        if sequence.location > start, sequence.location < boundary {
            return sequence.location - start
        }
        return proposed
    }
}
