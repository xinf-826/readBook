//
//  ReaderViewModel.swift
//  readBook
//
//  单本书的阅读态管理：全文加载、按章分页缓存、翻页导航、进度记忆与书签。
//  阅读位置统一以 (chapterIndex, characterOffset) 表示，排版变化后用偏移锚点恢复。
//

import SwiftUI
import UIKit
import Observation

@Observable
final class ReaderViewModel {
    let bookID: UUID
    let chapters: [Chapter]
    private(set) var bookmarks: [Bookmark]

    /// 加载失败标记（全文文件缺失或损坏）。
    private(set) var loadFailed = false

    var currentChapterIndex: Int
    var currentPageIndex: Int = 0
    /// 当前章节分页结果（区间相对章节文本）。
    private(set) var pages: [NSRange] = []

    private let store: BookStore
    private let fullText: NSString
    /// 各章节文本缓存（懒切分），LRU 最多保留最近 5 章。
    @ObservationIgnored private var chapterTextCache = LRUCache<Int, String>(capacity: 5)
    /// 各章节分页缓存：key = "chapterIndex-排版签名"，LRU 最多保留 10 条。
    @ObservationIgnored private var pageCache = LRUCache<String, [NSRange]>(capacity: 10)

    @ObservationIgnored private var containerSize: CGSize = .zero
    /// 实际渲染主题（跟随系统时由视图注入），决定文字颜色。
    @ObservationIgnored var displayTheme: ReaderTheme = .light

    init?(book: Book, store: BookStore) {
        guard let text = BookStorage.shared.loadFullText(for: book.id) else {
            self.bookID = book.id
            self.chapters = book.chapters
            self.bookmarks = book.bookmarks
            self.currentChapterIndex = 0
            self.store = store
            self.fullText = ""
            self.loadFailed = true
            return nil
        }
        self.bookID = book.id
        self.chapters = book.chapters.isEmpty
            ? [Chapter(index: 0, title: "正文", startOffset: 0, length: (text as NSString).length)]
            : book.chapters
        self.bookmarks = book.bookmarks
        self.store = store
        self.fullText = text as NSString
        self.currentChapterIndex = min(book.progress.chapterIndex, max(0, self.chapters.count - 1))
        self.pendingRestoreOffset = book.progress.characterOffset
    }

    /// 待恢复的章节内偏移（首次布局后定位页码）。
    @ObservationIgnored private var pendingRestoreOffset: Int = 0

    var settings: ReaderSettings { store.settings }

    // MARK: - 章节文本

    var currentChapter: Chapter {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex] : chapters[0]
    }

    func chapterText(_ index: Int) -> String {
        if let cached = chapterTextCache.value(for: index) { return cached }
        guard chapters.indices.contains(index) else { return "" }
        let ch = chapters[index]
        let safeRange = NSRange(location: ch.startOffset, length: min(ch.length, fullText.length - ch.startOffset))
        let text = safeRange.location >= 0 && safeRange.length >= 0 ? fullText.substring(with: safeRange) : ""
        chapterTextCache.set(text, for: index)
        return text
    }

    // MARK: - 分页

    private func styleSignature() -> String {
        let s = settings
        return "\(s.fontSize)-\(s.lineSpacing)-\(s.font.rawValue)-\(Int(containerSize.width))x\(Int(containerSize.height))"
    }

    private func style() -> TextStyle {
        TextStyle(settings: settings, textColor: UIColor(displayTheme.textColor))
    }

    /// 排版签名，用于驱动渲染层在字号/行距/字体/尺寸变化时重建。
    var layoutSignature: String { styleSignature() }

    /// 翻页内容标识，供 SwiftUI 在页码变化时可靠刷新。
    var pageContentID: String {
        "\(currentChapterIndex)-\(currentPageIndex)-\(layoutSignature)"
    }

    /// 容器尺寸变化或首次布局时调用，触发（必要时）重新分页并恢复位置。
    func updateLayout(containerSize: CGSize) {
        guard containerSize.width > 1, containerSize.height > 1 else { return }
        let changed = containerSize != self.containerSize
        self.containerSize = containerSize
        guard settings.readingMode == .paged else { return }
        if changed || pages.isEmpty {
            repaginateCurrentChapter(restoreOffset: currentOffsetInChapter())
        }
    }

    /// 设置变化后重新分页，保持当前阅读位置可见（仅翻页模式）。
    func reflowForSettingsChange() {
        guard settings.readingMode == .paged else { return }
        pageCache.removeAll()
        repaginateCurrentChapter(restoreOffset: currentOffsetInChapter())
    }

    private func repaginateCurrentChapter(restoreOffset: Int) {
        let key = "\(currentChapterIndex)-\(styleSignature())"
        if let cached = pageCache.value(for: key) {
            pages = cached
        } else {
            let result = PagedTextLayout.paginate(
                text: chapterText(currentChapterIndex),
                style: style(),
                contentSize: containerSize
            )
            pageCache.set(result, for: key)
            pages = result
        }
        currentPageIndex = PagedTextLayout.pageIndex(for: restoreOffset, in: pages)
    }

    private func currentOffsetInChapter() -> Int {
        if !pages.isEmpty, pages.indices.contains(currentPageIndex) {
            return pages[currentPageIndex].location
        }
        return pendingRestoreOffset
    }

    /// 当前章节内字符偏移。
    func characterOffsetInChapter() -> Int {
        settings.readingMode == .scroll ? pendingRestoreOffset : currentOffsetInChapter()
    }

    /// 将阅读位置同步到指定章节偏移。
    func applyReadingPosition(chapterIndex: Int, characterOffset: Int) {
        guard chapters.indices.contains(chapterIndex) else { return }
        currentChapterIndex = chapterIndex
        pendingRestoreOffset = max(0, characterOffset)
        if settings.readingMode == .paged {
            repaginateCurrentChapter(restoreOffset: pendingRestoreOffset)
        }
    }

    // MARK: - 渲染数据

    func attributedForCurrentPage() -> NSAttributedString {
        guard pages.indices.contains(currentPageIndex) else { return NSAttributedString(string: "") }
        let chapter = chapterText(currentChapterIndex) as NSString
        let range = pages[currentPageIndex]
        let safe = NSRange(location: range.location, length: min(range.length, chapter.length - range.location))
        guard safe.location >= 0, safe.length >= 0 else { return NSAttributedString(string: "") }
        return style().attributedString(
            chapter.substring(with: safe),
            baseOffsetInChapter: safe.location,
            chapterText: chapter as String
        )
    }

    func attributedForCurrentChapterScrolling() -> NSAttributedString {
        let chapter = chapterText(currentChapterIndex)
        return style().attributedString(chapter, chapterText: chapter)
    }

    // MARK: - 跨页寻址（供翻书渲染器使用）

    func pageRanges(forChapter index: Int) -> [NSRange] {
        let key = "\(index)-\(styleSignature())"
        if let cached = pageCache.value(for: key) { return cached }
        let result = PagedTextLayout.paginate(
            text: chapterText(index),
            style: style(),
            contentSize: containerSize
        )
        pageCache.set(result, for: key)
        return result
    }

    func pageCount(forChapter index: Int) -> Int { pageRanges(forChapter: index).count }

    func attributed(forChapter index: Int, page: Int) -> NSAttributedString {
        let ranges = pageRanges(forChapter: index)
        guard ranges.indices.contains(page) else { return NSAttributedString(string: "") }
        let chapter = chapterText(index) as NSString
        let r = ranges[page]
        let safe = NSRange(location: r.location, length: min(r.length, chapter.length - r.location))
        guard safe.location >= 0, safe.length >= 0 else { return NSAttributedString(string: "") }
        return style().attributedString(
            chapter.substring(with: safe),
            baseOffsetInChapter: safe.location,
            chapterText: chapter as String
        )
    }

    /// 下一页位置（跨章）。无下一页返回 nil。
    func nextPosition(chapter: Int, page: Int) -> (chapter: Int, page: Int)? {
        if page + 1 < pageCount(forChapter: chapter) { return (chapter, page + 1) }
        if chapter + 1 < chapters.count { return (chapter + 1, 0) }
        return nil
    }

    /// 上一页位置（跨章）。无上一页返回 nil。
    func prevPosition(chapter: Int, page: Int) -> (chapter: Int, page: Int)? {
        if page > 0 { return (chapter, page - 1) }
        if chapter > 0 {
            let c = chapter - 1
            return (c, max(0, pageCount(forChapter: c) - 1))
        }
        return nil
    }

    /// 翻书完成后同步当前位置。
    func setCurrentPosition(chapter: Int, page: Int) {
        guard chapters.indices.contains(chapter) else { return }
        currentChapterIndex = chapter
        pages = pageRanges(forChapter: chapter)
        currentPageIndex = page
    }

    // MARK: - 全局字符位置（底部进度展示）

    var globalCharacterPosition: Int { currentChapter.startOffset + currentOffsetInChapter() }
    var totalCharacterCount: Int { fullText.length }

    // MARK: - 翻页导航

    var totalPagesInChapter: Int { pages.count }
    var remainingPagesInChapter: Int { max(0, pages.count - currentPageIndex - 1) }

    func turnPage(forward: Bool) {
        if forward { nextPage() } else { previousPage() }
    }

    func nextPage() {
        if currentPageIndex + 1 < pages.count {
            currentPageIndex += 1
        } else if currentChapterIndex + 1 < chapters.count {
            currentChapterIndex += 1
            repaginateCurrentChapter(restoreOffset: 0)
            currentPageIndex = 0
        }
    }

    func previousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        } else if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            repaginateCurrentChapter(restoreOffset: Int.max)
            currentPageIndex = max(0, pages.count - 1)
        }
    }

    func goToChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentChapterIndex = index
        repaginateCurrentChapter(restoreOffset: 0)
        currentPageIndex = 0
    }

    /// 滚动模式下由渲染视图回报当前可见偏移。
    func updateScrollOffset(_ offset: Int) {
        pendingRestoreOffset = offset
    }

    // MARK: - 进度

    var globalProgressPercent: Double {
        guard fullText.length > 0 else { return 0 }
        let global = currentChapter.startOffset + currentOffsetInChapter()
        return Double(global).clamped(to: 0...Double(fullText.length)) / Double(fullText.length)
    }

    private func makeProgress() -> ReadingProgress {
        let offset = settings.readingMode == .scroll ? pendingRestoreOffset : currentOffsetInChapter()
        return ReadingProgress(
            chapterIndex: currentChapterIndex,
            characterOffset: offset,
            percent: globalProgressPercent
        )
    }

    /// 保存进度与书签（退出阅读器 / 切后台时调用）。
    func persist() {
        guard !loadFailed else { return }
        store.updateProgress(for: bookID, progress: makeProgress(), bookmarks: bookmarks)
    }

    // MARK: - 书签

    func addBookmarkAtCurrentPosition() {
        let chapter = chapterText(currentChapterIndex) as NSString
        let offset = currentOffsetInChapter()
        let previewLen = min(30, max(0, chapter.length - offset))
        let preview = previewLen > 0
            ? chapter.substring(with: NSRange(location: offset, length: previewLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            : currentChapter.title
        let bookmark = Bookmark(chapterIndex: currentChapterIndex, characterOffset: offset, preview: preview)
        bookmarks.append(bookmark)
        persist()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    func jumpTo(_ bookmark: Bookmark) {
        guard chapters.indices.contains(bookmark.chapterIndex) else { return }
        currentChapterIndex = bookmark.chapterIndex
        repaginateCurrentChapter(restoreOffset: bookmark.characterOffset)
    }

    /// 当前页是否已存在书签。
    var currentPositionBookmarked: Bool {
        let offset = currentOffsetInChapter()
        return bookmarks.contains { $0.chapterIndex == currentChapterIndex && abs($0.characterOffset - offset) < 5 }
    }
}
