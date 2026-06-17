//
//  PagedTextLayout.swift
//  readBook
//
//  翻页排版引擎：分页测量与单页绘制共用同一套 TextKit 栈，保证边界一致。
//

import UIKit

// MARK: - TextKit 栈

/// 固定高度 textContainer，分页与绘制共用。
final class PageTextKitStack {
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer()

    init(contentSize: CGSize) {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.size = contentSize
    }

    func updateContentSize(_ size: CGSize) {
        guard textContainer.size != size else { return }
        textContainer.size = size
    }

    func layout(_ attributed: NSAttributedString) {
        textStorage.setAttributedString(attributed)
        layoutManager.ensureLayout(for: textContainer)
    }

    /// 当前容器内完整排版的字符数。
    var fittedCharacterCount: Int {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return 0 }
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).length
    }

    func draw(at origin: CGPoint) {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

// MARK: - 分页

enum PagedTextLayout {

    /// 将章节文本切分为页，返回每页字符区间（相对章节文本）。
    static func paginate(text: String, style: TextStyle, contentSize: CGSize) -> [NSRange] {
        let ns = text as NSString
        let totalLength = ns.length
        guard contentSize.width > 1, contentSize.height > 1, totalLength > 0 else {
            return [NSRange(location: 0, length: totalLength)]
        }

        var ranges: [NSRange] = []
        var start = 0
        while start < totalLength {
            let fitLength = fittedLength(
                chapter: text,
                start: start,
                style: style,
                contentSize: contentSize
            )
            let pageLength = max(1, min(fitLength, totalLength - start))
            ranges.append(NSRange(location: start, length: pageLength))
            start += pageLength
        }
        return ranges.isEmpty ? [NSRange(location: 0, length: totalLength)] : ranges
    }

    /// 二分查找：固定高度容器内能完整排版的最多字符数。
    private static func fittedLength(
        chapter: String,
        start: Int,
        style: TextStyle,
        contentSize: CGSize
    ) -> Int {
        let ns = chapter as NSString
        let remaining = ns.length - start
        guard remaining > 0 else { return 0 }

        let stack = PageTextKitStack(contentSize: contentSize)
        var low = 1
        var high = remaining
        var best = 1

        while low <= high {
            let mid = (low + high) / 2
            let slice = ns.substring(with: NSRange(location: start, length: mid))
            let attr = style.attributedString(slice, baseOffsetInChapter: start, chapterText: chapter)
            stack.layout(attr)
            if stack.fittedCharacterCount >= mid {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    static func pageIndex(for characterOffset: Int, in pages: [NSRange]) -> Int {
        guard !pages.isEmpty else { return 0 }
        for (i, range) in pages.enumerated() {
            if characterOffset < range.location + range.length { return i }
        }
        return pages.count - 1
    }
}

// MARK: - 单页绘制

/// 翻页模式单页画布，与 PagedTextLayout 共用 TextKit 栈。
final class PageTextCanvasView: UIView {
    private let stack: PageTextKitStack
    private var contentInsets = UIEdgeInsets.zero

    override init(frame: CGRect) {
        stack = PageTextKitStack(contentSize: .zero)
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .topLeft
    }

    required init?(coder: NSCoder) { nil }

    func update(attributed: NSAttributedString, contentSize: CGSize, insets: UIEdgeInsets) {
        contentInsets = insets
        stack.updateContentSize(contentSize)
        stack.layout(attributed)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        stack.draw(at: CGPoint(x: contentInsets.left, y: contentInsets.top))
    }
}
