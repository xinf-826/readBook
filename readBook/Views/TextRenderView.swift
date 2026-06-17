//
//  TextRenderView.swift
//  readBook
//
//  文本渲染：翻页模式单页画布 + 滚动模式整章视图。
//

import SwiftUI
import UIKit

/// SwiftUI 包装：翻页单页 TextKit 画布。
struct PageTextCanvas: UIViewRepresentable {
    let attributed: NSAttributedString
    let insets: UIEdgeInsets
    let contentSize: CGSize

    func makeUIView(context: Context) -> PageTextCanvasView {
        let view = PageTextCanvasView(frame: .zero)
        view.update(attributed: attributed, contentSize: contentSize, insets: insets)
        return view
    }

    func updateUIView(_ uiView: PageTextCanvasView, context: Context) {
        uiView.update(attributed: attributed, contentSize: contentSize, insets: insets)
    }
}

/// 翻页模式：左/右翻页（200ms 延迟），中间呼出菜单。
struct PagedReaderView: View {
    let attributed: NSAttributedString
    let pageID: String
    let insets: UIEdgeInsets
    let contentSize: CGSize
    let onCenterTap: () -> Void
    let onTurnPage: (_ forward: Bool) -> Void

    @State private var isPaging = false
    private let pageTurnDelayNs: UInt64 = 200_000_000

    var body: some View {
        GeometryReader { geo in
            PageTextCanvas(attributed: attributed, insets: insets, contentSize: contentSize)
                .id(pageID)
                .frame(
                    width: geo.size.width,
                    height: contentSize.height + insets.top + insets.bottom,
                    alignment: .topLeading
                )

            HStack(spacing: 0) {
                tapZone { turnPage(forward: false) }
                    .frame(width: geo.size.width * 0.3)
                tapZone(onCenterTap)
                tapZone { turnPage(forward: true) }
                    .frame(width: geo.size.width * 0.3)
            }
            .allowsHitTesting(!isPaging)
        }
    }

    private func turnPage(forward: Bool) {
        guard !isPaging else { return }
        isPaging = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: pageTurnDelayNs)
            onTurnPage(forward)
            isPaging = false
        }
    }

    private func tapZone(_ action: @escaping () -> Void) -> some View {
        Color.clear.contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

/// 整章滚动渲染（滚动模式）。回调上报当前可见文本的字符偏移用于进度记忆；点击呼出菜单。
struct ScrollingTextView: UIViewRepresentable {
    let attributed: NSAttributedString
    let insets: UIEdgeInsets
    let initialOffset: Int
    let onVisibleOffsetChange: (Int) -> Void
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibleOffsetChange: onVisibleOffsetChange, onTap: onTap)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: false)
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.textContainerInset = insets
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.attributedText = attributed

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)

        context.coordinator.scrollToOffset(initialOffset, in: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.textContainerInset = insets
        if !uiView.attributedText.isEqual(to: attributed) {
            uiView.attributedText = attributed
            context.coordinator.scrollToOffset(initialOffset, in: uiView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let onVisibleOffsetChange: (Int) -> Void
        let onTap: () -> Void
        private var didInitialScroll = false

        init(onVisibleOffsetChange: @escaping (Int) -> Void, onTap: @escaping () -> Void) {
            self.onVisibleOffsetChange = onVisibleOffsetChange
            self.onTap = onTap
        }

        @objc func handleTap() { onTap() }

        func scrollToOffset(_ offset: Int, in tv: UITextView) {
            guard offset > 0, offset < tv.textStorage.length else { return }
            let range = NSRange(location: offset, length: 0)
            DispatchQueue.main.async {
                tv.layoutIfNeeded()
                tv.scrollRangeToVisible(range)
                self.didInitialScroll = true
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard didInitialScroll, let tv = scrollView as? UITextView else { return }
            let point = CGPoint(x: tv.textContainerInset.left + 1,
                                y: tv.contentOffset.y + tv.textContainerInset.top + 1)
            if let pos = tv.closestPosition(to: point) {
                let offset = tv.offset(from: tv.beginningOfDocument, to: pos)
                onVisibleOffsetChange(offset)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
