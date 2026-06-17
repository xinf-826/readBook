//
//  BookStorage.swift
//  readBook
//
//  本地持久化层。元数据以 JSON 存于 Documents/books/<id>.json，
//  全文以纯文本存于 Documents/texts/<id>.txt，全局设置存于 Documents/settings.json。
//  所有磁盘写操作经串行队列，避免并发写冲突。
//

import Foundation

enum BookStorageError: LocalizedError {
    case writeFailed(String)
    case deletedWhileSaving(UUID)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let detail): detail
        case .deletedWhileSaving(let id): "书籍 \(id) 已在保存前被删除"
        }
    }
}

final class BookStorage {
    static let shared = BookStorage()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.readbook.storage.io")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// 删除后递增 generation，使已排队的 save 操作失效，避免竞态重建。
    private var bookGenerations: [UUID: Int] = [:]

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        createDirectoriesIfNeeded()
    }

    // MARK: - 目录

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var booksDir: URL { documentsURL.appendingPathComponent("books", isDirectory: true) }
    private var textsDir: URL { documentsURL.appendingPathComponent("texts", isDirectory: true) }
    private var settingsURL: URL { documentsURL.appendingPathComponent("settings.json") }

    var hasPersistedSettings: Bool {
        fileManager.fileExists(atPath: settingsURL.path)
    }

    private func createDirectoriesIfNeeded() {
        for dir in [booksDir, textsDir] {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func metaURL(for id: UUID) -> URL { booksDir.appendingPathComponent("\(id.uuidString).json") }
    private func textURL(for id: UUID) -> URL { textsDir.appendingPathComponent("\(id.uuidString).txt") }

    // MARK: - 书籍元数据

    /// 加载全部书籍元数据。单本解析失败时跳过并记录，不影响其它书籍。
    func loadAllBooks() -> [Book] {
        createDirectoriesIfNeeded()
        guard let files = try? fileManager.contentsOfDirectory(at: booksDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var books: [Book] = []
        for url in files where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let book = try decoder.decode(Book.self, from: data)
                books.append(book)
            } catch {
                print("[BookStorage] 跳过损坏的书籍元数据 \(url.lastPathComponent): \(error)")
            }
        }
        return books
    }

    /// 保存（或更新）书籍元数据。`generation` 为调用方发起保存时的版本号，删除后会失效。
    func saveBook(_ book: Book, generation: Int? = nil, completion: ((Result<Void, BookStorageError>) -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let result = self.performSaveBook(book, generation: generation)
            if let completion {
                DispatchQueue.main.async { completion(result) }
            } else if case .failure(let error) = result {
                print("[BookStorage] 保存书籍失败 \(book.id): \(error.localizedDescription)")
            }
        }
    }

    /// 同步保存，供导入等关键路径使用，确保写入成功后再更新 UI。
    @discardableResult
    func saveBookSync(_ book: Book) throws {
        try ioQueue.sync {
            switch performSaveBook(book, generation: nil) {
            case .success: return
            case .failure(let error): throw error
            }
        }
    }

    private func performSaveBook(_ book: Book, generation: Int?) -> Result<Void, BookStorageError> {
        if let generation, bookGenerations[book.id, default: 0] != generation {
            return .failure(.deletedWhileSaving(book.id))
        }
        do {
            let data = try encoder.encode(book)
            try data.write(to: metaURL(for: book.id), options: .atomic)
            return .success(())
        } catch {
            return .failure(.writeFailed("保存书籍失败：\(error.localizedDescription)"))
        }
    }

    /// 删除书籍：同时清理元数据与全文文件，并使该 book 的待保存操作失效。
    func deleteBook(_ book: Book, completion: ((Result<Void, BookStorageError>) -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let result = self.performDeleteBook(book)
            if let completion {
                DispatchQueue.main.async { completion(result) }
            } else if case .failure(let error) = result {
                print("[BookStorage] 删除书籍失败 \(book.id): \(error.localizedDescription)")
            }
        }
    }

    private func performDeleteBook(_ book: Book) -> Result<Void, BookStorageError> {
        bookGenerations[book.id, default: 0] += 1
        do {
            if fileManager.fileExists(atPath: metaURL(for: book.id).path) {
                try fileManager.removeItem(at: metaURL(for: book.id))
            }
            if fileManager.fileExists(atPath: textURL(for: book.id).path) {
                try fileManager.removeItem(at: textURL(for: book.id))
            }
            return .success(())
        } catch {
            return .failure(.writeFailed("删除书籍失败：\(error.localizedDescription)"))
        }
    }

    /// 发起保存时获取当前 generation，删除后该 token 失效。
    func bookGeneration(for id: UUID) -> Int {
        ioQueue.sync { bookGenerations[id, default: 0] }
    }

    // MARK: - 全文

    /// 写入全文（导入时调用）。失败时抛出错误。
    func saveFullText(_ text: String, for id: UUID) throws {
        try ioQueue.sync {
            guard let data = text.data(using: .utf8) else {
                throw BookStorageError.writeFailed("全文编码失败")
            }
            do {
                try data.write(to: textURL(for: id), options: .atomic)
            } catch {
                throw BookStorageError.writeFailed("保存全文失败：\(error.localizedDescription)")
            }
        }
    }

    /// 读取全文（打开阅读器时调用）。文件缺失或损坏时返回 nil。
    func loadFullText(for id: UUID) -> String? {
        guard let data = try? Data(contentsOf: textURL(for: id)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 全局设置

    func loadSettings() -> ReaderSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(ReaderSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func saveSettings(_ settings: ReaderSettings, completion: ((Result<Void, BookStorageError>) -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<Void, BookStorageError>
            do {
                let data = try self.encoder.encode(settings)
                try data.write(to: self.settingsURL, options: .atomic)
                result = .success(())
            } catch {
                result = .failure(.writeFailed("保存设置失败：\(error.localizedDescription)"))
            }
            if let completion {
                DispatchQueue.main.async { completion(result) }
            } else if case .failure(let error) = result {
                print("[BookStorage] 保存设置失败: \(error.localizedDescription)")
            }
        }
    }
}
