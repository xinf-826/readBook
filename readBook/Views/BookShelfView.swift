//
//  BookShelfView.swift
//  readBook
//
//  书架首页：网格/列表视图切换、搜索、空状态引导、导入与书籍管理。
//

import SwiftUI
import UniformTypeIdentifiers

struct BookShelfView: View {
    @Environment(BookStore.self) private var store

    @AppStorage("shelf.isGrid") private var isGrid = true
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showLANImport = false
    @State private var readingBook: Book?
    @State private var pendingDelete: Book?
    @State private var showOnboarding = false

    private var displayedBooks: [Book] { store.search(searchText) }
    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    emptyState
                } else if displayedBooks.isEmpty && isSearching {
                    searchEmptyState
                } else if isGrid {
                    gridContent
                } else {
                    listContent
                }
            }
            .navigationTitle("书架")
            .toolbar { toolbarContent }
            .searchable(text: $searchText, prompt: "搜索书名")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, UTType(filenameExtension: "txt")!],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showLANImport) {
                LANImportView()
                    .environment(store)
            }
            .fullScreenCover(item: $readingBook) { book in
                ReaderView(book: book)
                    .environment(store)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView {
                    hasSeenOnboarding = true
                    showOnboarding = false
                }
                .interactiveDismissDisabled()
            }
            .onAppear {
                if !hasSeenOnboarding { showOnboarding = true }
            }
            .alert("删除书籍", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { book in
                Button("删除", role: .destructive) { store.delete(book) }
                Button("取消", role: .cancel) {}
            } message: { book in
                Text("确定删除《\(book.title)》？该操作不可恢复。")
            }
            .alert("导入失败", isPresented: Binding(
                get: { store.importError != nil },
                set: { if !$0 { store.importError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(store.importError ?? "")
            }
            .alert("保存失败", isPresented: Binding(
                get: { store.storageError != nil },
                set: { if !$0 { store.storageError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(store.storageError ?? "")
            }
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { isGrid.toggle() } label: {
                Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
            }
            .accessibilityLabel(isGrid ? "切换为列表视图" : "切换为网格视图")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showImporter = true } label: {
                    Label("文件导入", systemImage: "square.and.arrow.down")
                }
                Button { showLANImport = true } label: {
                    Label("局域网导入", systemImage: "wifi")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("导入书籍")
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        ContentUnavailableView {
            Label("书架空空如也", systemImage: "books.vertical")
        } description: {
            Text("从「文件」导入 .txt 小说开始阅读")
        } actions: {
            Menu {
                Button { showImporter = true } label: {
                    Label("文件导入", systemImage: "square.and.arrow.down")
                }
                Button { showLANImport = true } label: {
                    Label("局域网导入", systemImage: "wifi")
                }
            } label: {
                Label("导入书籍", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var searchEmptyState: some View {
        ContentUnavailableView {
            Label("未找到匹配的书籍", systemImage: "magnifyingglass")
        } description: {
            Text("没有书名包含「\(searchText)」的书籍")
        }
    }

    // MARK: - 网格

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 16)], spacing: 20) {
                ForEach(displayedBooks) { book in
                    Button { readingBook = book } label: {
                        BookGridCell(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { bookContextMenu(book) }
                }
            }
            .padding()
        }
        .refreshable { store.reload() }
    }

    // MARK: - 列表

    private var listContent: some View {
        List(displayedBooks) { book in
            Button { readingBook = book } label: {
                BookListRow(book: book)
            }
            .buttonStyle(.plain)
            .contextMenu { bookContextMenu(book) }
        }
        .listStyle(.plain)
        .refreshable { store.reload() }
    }

    @ViewBuilder
    private func bookContextMenu(_ book: Book) -> some View {
        if !book.isFinished {
            Button { store.markAsFinished(book) } label: {
                Label("标记为已读", systemImage: "checkmark.circle")
            }
        }
        Button(role: .destructive) { pendingDelete = book } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            store.importBooks(from: urls)
        case .failure(let error):
            store.importError = error.localizedDescription
        }
    }
}

// MARK: - 网格卡片

private struct BookGridCell: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCoverView(title: book.title)
            Text(book.title)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.primary)
            ProgressLabel(book: book)
        }
    }
}

// MARK: - 列表行

private struct BookListRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(title: book.title)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(book.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressLabel(book: book)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ProgressLabel: View {
    let book: Book

    var body: some View {
        HStack(spacing: 4) {
            if book.isFinished {
                Text("已读完")
            } else if book.progress.percent > 0 {
                Text("已读 \(Int(book.progress.percent * 100))%")
            } else {
                Text("未读")
            }
            if let date = book.lastReadDate {
                Text("· \(date.formatted(.relative(presentation: .named)))")
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
