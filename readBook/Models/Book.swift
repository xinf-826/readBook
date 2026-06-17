//
//  Book.swift
//  readBook
//
//  书籍领域模型。元数据与全文分离存储：本模型只持有元数据与章节索引，
//  全文按 bookID 单独存放于 Documents/texts/，按需加载。
//

import Foundation

/// 单个章节的索引信息（相对于全文的字符区间）。
struct Chapter: Codable, Identifiable, Hashable {
    var id: Int { index }
    /// 章节在书内的顺序索引（从 0 开始）。
    var index: Int
    var title: String
    /// 章节正文在全文中的起始字符偏移。
    var startOffset: Int
    /// 章节正文长度（字符数）。
    var length: Int

    init(index: Int, title: String, startOffset: Int, length: Int) {
        self.index = index
        self.title = title
        self.startOffset = startOffset
        self.length = length
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = (try? c.decodeIfPresent(Int.self, forKey: .index)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "未命名章节"
        startOffset = (try? c.decodeIfPresent(Int.self, forKey: .startOffset)) ?? 0
        length = (try? c.decodeIfPresent(Int.self, forKey: .length)) ?? 0
    }
}

/// 阅读进度。位置以 (章节索引, 章节内字符偏移) 表示，避免页码因排版变化而失真。
struct ReadingProgress: Codable, Hashable {
    var chapterIndex: Int
    var characterOffset: Int
    /// 整书进度百分比缓存（0.0–1.0），用于书架展示，避免重复计算。
    var percent: Double

    static let zero = ReadingProgress(chapterIndex: 0, characterOffset: 0, percent: 0)

    init(chapterIndex: Int, characterOffset: Int, percent: Double) {
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.percent = percent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chapterIndex = (try? c.decodeIfPresent(Int.self, forKey: .chapterIndex)) ?? 0
        characterOffset = (try? c.decodeIfPresent(Int.self, forKey: .characterOffset)) ?? 0
        percent = (try? c.decodeIfPresent(Double.self, forKey: .percent)) ?? 0
    }
}

/// 书签。记录位置并缓存预览文字（当前段落前 30 字）。
struct Bookmark: Codable, Identifiable, Hashable {
    var id: UUID
    var chapterIndex: Int
    var characterOffset: Int
    var preview: String
    var createdDate: Date

    init(id: UUID = UUID(), chapterIndex: Int, characterOffset: Int, preview: String, createdDate: Date = Date()) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.preview = preview
        self.createdDate = createdDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        chapterIndex = (try? c.decodeIfPresent(Int.self, forKey: .chapterIndex)) ?? 0
        characterOffset = (try? c.decodeIfPresent(Int.self, forKey: .characterOffset)) ?? 0
        preview = (try? c.decodeIfPresent(String.self, forKey: .preview)) ?? ""
        createdDate = (try? c.decodeIfPresent(Date.self, forKey: .createdDate)) ?? Date()
    }
}

/// 书籍元数据。Codable 解码对所有字段做缺失防御，保证旧版本数据向后兼容。
struct Book: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var author: String?
    var addedDate: Date
    var lastReadDate: Date?
    var chapters: [Chapter]
    var progress: ReadingProgress
    var bookmarks: [Bookmark]
    /// 是否已标记为读完。
    var isFinished: Bool

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        addedDate: Date = Date(),
        lastReadDate: Date? = nil,
        chapters: [Chapter] = [],
        progress: ReadingProgress = .zero,
        bookmarks: [Bookmark] = [],
        isFinished: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.addedDate = addedDate
        self.lastReadDate = lastReadDate
        self.chapters = chapters
        self.progress = progress
        self.bookmarks = bookmarks
        self.isFinished = isFinished
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "未命名书籍"
        author = try? c.decodeIfPresent(String.self, forKey: .author)
        addedDate = (try? c.decodeIfPresent(Date.self, forKey: .addedDate)) ?? Date()
        lastReadDate = try? c.decodeIfPresent(Date.self, forKey: .lastReadDate)
        chapters = (try? c.decodeIfPresent([Chapter].self, forKey: .chapters)) ?? []
        progress = (try? c.decodeIfPresent(ReadingProgress.self, forKey: .progress)) ?? .zero
        bookmarks = (try? c.decodeIfPresent([Bookmark].self, forKey: .bookmarks)) ?? []
        isFinished = (try? c.decodeIfPresent(Bool.self, forKey: .isFinished)) ?? false
    }

    /// 用于占位封面与排序展示。
    var displayAuthor: String { (author?.isEmpty == false ? author! : "未知作者") }
}
