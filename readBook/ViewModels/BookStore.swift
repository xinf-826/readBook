//
//  BookStore.swift
//  readBook
//
//  全局书籍管理：加载/导入/删除/标记已读，以及全局阅读设置。
//

import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

@Observable
final class BookStore {
    private(set) var books: [Book] = []
    var settings: ReaderSettings {
        didSet { storage.saveSettings(settings) }
    }

    /// 导入过程中的错误提示（供 UI 展示）。
    var importError: String?
    /// 持久化失败提示（供 UI 展示）。
    var storageError: String?

    private let storage = BookStorage.shared

    init() {
        let isFreshInstall = !storage.hasPersistedSettings
        settings = storage.loadSettings()
        if isFreshInstall {
            settings.brightness = Double(UIScreen.main.brightness).clamped(to: 0.2...1.0)
        }
        reload()
    }

    /// 重新从磁盘加载全部书籍，按最后阅读时间倒序（未读排后）。
    func reload() {
        books = storage.loadAllBooks().sorted(by: Self.sortRule)
    }

    private static func sortRule(_ a: Book, _ b: Book) -> Bool {
        switch (a.lastReadDate, b.lastReadDate) {
        case let (l?, r?): return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.addedDate > b.addedDate
        }
    }

    private func resort() { books.sort(by: Self.sortRule) }

    // MARK: - 导入

    /// 批量导入选中的文件 URL。逐个解析，单个失败不影响其余。
    func importBooks(from urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do {
                try importBook(from: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        importError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        resort()
    }

    /// 从内存数据导入单本书，返回状态文案（供局域网上传页展示）。
    @discardableResult
    func importBook(data: Data, fileName: String) -> String {
        do {
            try importBook(fromData: data, fileName: fileName)
            resort()
            return "导入成功"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }

    private func importBook(from url: URL) throws {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try importBook(fromData: data, fileName: url.lastPathComponent)
    }

    private func importBook(fromData data: Data, fileName: String) throws {
        let parsed = try FileParser.parse(data: data, fileName: fileName)
        let book = Book(
            title: parsed.title,
            chapters: parsed.chapters,
            progress: .zero
        )
        try storage.saveFullText(parsed.fullText, for: book.id)
        try storage.saveBookSync(book)
        books.append(book)
    }

    // MARK: - 管理

    func delete(_ book: Book) {
        storage.deleteBook(book) { [weak self] result in
            if case .failure(let error) = result {
                self?.storageError = error.localizedDescription
            }
        }
        books.removeAll { $0.id == book.id }
    }

    func markAsFinished(_ book: Book) {
        guard let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[idx].isFinished = true
        books[idx].progress.percent = 1.0
        persistBook(books[idx])
    }

    /// 阅读器退出/切后台时更新进度并落盘。
    func updateProgress(for bookID: UUID, progress: ReadingProgress, bookmarks: [Bookmark]) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].progress = progress
        books[idx].bookmarks = bookmarks
        books[idx].lastReadDate = Date()
        if progress.percent >= 1.0 { books[idx].isFinished = true }
        persistBook(books[idx])
        resort()
    }

    private func persistBook(_ book: Book) {
        let generation = storage.bookGeneration(for: book.id)
        storage.saveBook(book, generation: generation) { [weak self] result in
            if case .failure(let error) = result {
                self?.storageError = error.localizedDescription
            }
        }
    }

    func search(_ keyword: String) -> [Book] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return books }
        let lowered = trimmed.lowercased()
        return books.filter { book in
            book.title.localizedCaseInsensitiveContains(trimmed)
                || Self.pinyin(of: book.title).contains(lowered)
        }
    }

    /// 将中文转为无声调拼音，用于模糊搜索。
    private static func pinyin(of string: String) -> String {
        let mutable = NSMutableString(string: string)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }
}
