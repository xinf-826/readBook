//
//  ChapterListView.swift
//  readBook
//
//  目录与书签：章节列表（当前章节高亮、点击跳转）+ 书签列表（预览、跳转、删除）。
//

import SwiftUI

struct ChapterListView: View {
    let vm: ReaderViewModel
    let onJump: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("目录").tag(0)
                    Text("书签").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if tab == 0 {
                    chapterList
                } else {
                    bookmarkList
                }
            }
            .navigationTitle(tab == 0 ? "目录" : "书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var chapterList: some View {
        List(vm.chapters) { chapter in
            Button {
                vm.goToChapter(chapter.index)
                onJump()
                dismiss()
            } label: {
                HStack {
                    Text(chapter.title)
                        .lineLimit(1)
                        .foregroundStyle(chapter.index == vm.currentChapterIndex ? Color.accentColor : .primary)
                    Spacer()
                    if chapter.index == vm.currentChapterIndex {
                        Image(systemName: "book.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var bookmarkList: some View {
        if vm.bookmarks.isEmpty {
            ContentUnavailableView("暂无书签", systemImage: "bookmark", description: Text("在阅读页点击书签按钮添加"))
        } else {
            List {
                ForEach(vm.bookmarks.sorted(by: { $0.createdDate > $1.createdDate })) { bookmark in
                    Button {
                        vm.jumpTo(bookmark)
                        onJump()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapterTitle(for: bookmark))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(bookmark.preview.isEmpty ? "（无预览）" : bookmark.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { indexSet in
                    let sorted = vm.bookmarks.sorted(by: { $0.createdDate > $1.createdDate })
                    for i in indexSet { vm.removeBookmark(sorted[i]) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func chapterTitle(for bookmark: Bookmark) -> String {
        vm.chapters.indices.contains(bookmark.chapterIndex) ? vm.chapters[bookmark.chapterIndex].title : "未知章节"
    }
}
