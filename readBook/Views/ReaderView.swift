//
//  ReaderView.swift
//  readBook
//
//  阅读器核心页面：翻页/滚动渲染、左右中点击区域、设置菜单、进度展示、位置记忆。
//

import SwiftUI

struct ReaderView: View {
    let book: Book
    @Environment(BookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @State private var vm: ReaderViewModel?
    @State private var showMenu = false
    @State private var showSettings = false
    @State private var showChapters = false
    /// 进入阅读器前的系统屏幕亮度，退出时恢复。
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness

    // MARK: - 听书（已暂停，见 BACKLOG.md）
    // @State private var audioVM: AudioPlayerViewModel?

    private var settings: ReaderSettings { store.settings }

    /// 实际生效主题：跟随系统时按 colorScheme 选用 light/night。
    private var theme: ReaderTheme {
        guard settings.followSystem else { return settings.theme }
        return colorScheme == .dark ? .night : .light
    }

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            if let vm {
                if vm.loadFailed {
                    failureView
                } else {
                    readerContent(vm)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            slimTopBar(vm)
                        }
                        .overlay(alignment: .bottom) {
                            if showMenu { controlRow }
                        }
                }
            } else {
                ProgressView().tint(theme.textColor)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(settings.followSystem ? nil : (theme.isDark ? .dark : .light))
        .onAppear {
            loadIfNeeded()
            savedBrightness = UIScreen.main.brightness
            applyBrightness()
        }
        .onDisappear { restoreBrightness() }
        .onChange(of: settings) { _, _ in
            if settings.readingMode == .paged {
                vm?.reflowForSettingsChange()
            }
            applyBrightness()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                applyBrightness()
            } else {
                restoreBrightness()
                vm?.persist()
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView()
                .environment(store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChapters) {
            if let vm {
                ChapterListView(vm: vm) { showChapters = false }
                    .presentationDetents([.large])
            }
        }
        // 听书全屏面板（已暂停，见 BACKLOG.md）
        // .sheet(isPresented: Binding(
        //     get: { audioVM?.showFullPanel ?? false },
        //     set: { audioVM?.showFullPanel = $0 }
        // )) {
        //     if let vm, let audioVM {
        //         AudioFullPanel(
        //             audioVM: audioVM,
        //             theme: theme,
        //             chapterText: vm.chapterText(vm.currentChapterIndex)
        //         )
        //     }
        // }
    }

    private func loadIfNeeded() {
        guard vm == nil else { return }
        vm = ReaderViewModel(book: book, store: store)
    }

    private func toggleMenu() {
        withAnimation(.easeInOut(duration: 0.2)) { showMenu.toggle() }
    }

    // MARK: - 内容渲染

    @ViewBuilder
    private func readerContent(_ vm: ReaderViewModel) -> some View {
        GeometryReader { geo in
            let textInsets = ReaderLayout.textInsets(safeAreaBottom: geo.safeAreaInsets.bottom)
            let paginationSize = CGSize(
                width: max(1, geo.size.width - textInsets.left - textInsets.right),
                height: max(1, geo.size.height - textInsets.top - textInsets.bottom)
            )
            let _ = vm.updateLayout(containerSize: paginationSize)
            let _ = (vm.displayTheme = theme)
            Group {
                if settings.readingMode == .scroll {
                    ScrollingTextView(
                        attributed: vm.attributedForCurrentChapterScrolling(),
                        insets: textInsets,
                        initialOffset: 0,
                        onVisibleOffsetChange: { vm.updateScrollOffset($0) },
                        onTap: { toggleMenu() }
                    )
                    .id("scroll-\(vm.currentChapterIndex)-\(vm.layoutSignature)-\(theme.rawValue)")
                } else {
                    PagedReaderView(
                        attributed: vm.attributedForCurrentPage(),
                        pageID: vm.pageContentID,
                        insets: textInsets,
                        contentSize: paginationSize,
                        onCenterTap: { toggleMenu() },
                        onTurnPage: { vm.turnPage(forward: $0) }
                    )
                    .id("paged-\(vm.layoutSignature)-\(theme.rawValue)")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - 亮度（直接控制系统屏幕亮度）

    private func applyBrightness() {
        UIScreen.main.brightness = settings.brightness
    }

    private func restoreBrightness() {
        UIScreen.main.brightness = savedBrightness
    }

    private func slimTopBar(_ vm: ReaderViewModel) -> some View {
        HStack(spacing: 6) {
            Button { vm.persist(); dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            Text("本地书")
            Text(vm.currentChapter.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if showMenu {
                Button { toggleBookmark(vm) } label: {
                    Image(systemName: vm.currentPositionBookmarked ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(theme.secondaryTextColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(theme.backgroundColor)
    }

    private var controlRow: some View {
        HStack(spacing: 44) {
            menuButton("目录", "list.bullet") { showChapters = true }
            // menuButton("听书", "headphones") { startAudioMode() } // 已暂停，见 BACKLOG.md
            menuButton("设置", "textformat.size") { showSettings = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.bottom, 8)
        .background(theme.backgroundColor.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.secondaryTextColor.opacity(0.15)).frame(height: 0.5)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func menuButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption)
            }
        }
        .foregroundStyle(theme.textColor)
    }

    private func toggleBookmark(_ vm: ReaderViewModel) {
        if let existing = vm.bookmarks.first(where: {
            $0.chapterIndex == vm.currentChapterIndex
        }), vm.currentPositionBookmarked {
            vm.removeBookmark(existing)
        } else {
            vm.addBookmarkAtCurrentPosition()
        }
    }

    // private func startAudioMode() {
    //     guard let vm else { return }
    //     withAnimation(.easeInOut(duration: 0.2)) { showMenu = false }
    //     if audioVM == nil {
    //         audioVM = AudioPlayerViewModel(readerVM: vm, bookTitle: book.title)
    //     }
    //     audioVM?.start()
    // }

    private var failureView: some View {
        ContentUnavailableView {
            Label("无法打开本书", systemImage: "exclamationmark.triangle")
        } description: {
            Text("全文文件缺失或已损坏")
        } actions: {
            Button("返回") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}
