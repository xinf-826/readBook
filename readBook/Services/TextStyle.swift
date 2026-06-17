//
//  TextStyle.swift
//  readBook
//
//  统一生成正文排版属性（字体 / 行距 / 颜色），供分页测量与渲染共用。
//

import UIKit

struct TextStyle {
    let font: UIFont
    let lineSpacing: CGFloat
    let textColor: UIColor
    /// 段落首行缩进两字符。
    var firstLineHeadIndent: CGFloat { font.pointSize * 2 }

    init(settings: ReaderSettings, textColor: UIColor) {
        if let name = settings.font.fontName, let custom = UIFont(name: name, size: settings.fontSize) {
            self.font = custom
        } else {
            self.font = UIFont.systemFont(ofSize: settings.fontSize)
        }
        self.lineSpacing = settings.lineSpacing
        self.textColor = textColor
    }

    func makeParagraphStyle(firstLineIndented: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = lineSpacing * 1.5
        style.firstLineHeadIndent = firstLineIndented ? firstLineHeadIndent : 0
        style.lineBreakMode = .byWordWrapping
        return style
    }

    func attributes(firstLineIndented: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: makeParagraphStyle(firstLineIndented: firstLineIndented)
        ]
    }

    /// 按段落分别设置首行缩进，保证分页测量与 UITextView 渲染排版一致。
    func attributedString(
        _ text: String,
        baseOffsetInChapter: Int = 0,
        chapterText: String? = nil
    ) -> NSAttributedString {
        let context = chapterText ?? text
        let ns = text as NSString
        let result = NSMutableAttributedString(string: text)
        guard ns.length > 0 else { return result }

        var loc = 0
        while loc < ns.length {
            let paraRange = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let globalOffset = baseOffsetInChapter + paraRange.location
            let indented = Self.isParagraphStart(in: context, at: globalOffset)
            result.addAttributes(attributes(firstLineIndented: indented), range: paraRange)
            loc = NSMaxRange(paraRange)
        }
        return result
    }

    /// 判断章节内某偏移是否处于段落起始（段首才应首行缩进）。
    static func isParagraphStart(in text: String, at offset: Int) -> Bool {
        guard offset > 0 else { return true }
        let ns = text as NSString
        guard offset <= ns.length else { return true }
        let prev = ns.character(at: offset - 1)
        return prev == 0x0A || prev == 0x0D
    }
}
