//
//  ReaderLayout.swift
//  readBook
//
//  阅读器布局常量，分页测量与渲染层共用。
//

import UIKit

enum ReaderLayout {
    static let horizontalInset: CGFloat = 20
    static let topInset: CGFloat = 12
    /// 可视区域底部留白（不含 home indicator 安全区）。
    static let bottomSpacing: CGFloat = 20

    static func textInsets(safeAreaBottom: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: topInset,
            left: horizontalInset,
            bottom: bottomSpacing + safeAreaBottom,
            right: horizontalInset
        )
    }
}
