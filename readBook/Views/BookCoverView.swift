//
//  BookCoverView.swift
//  readBook
//
//  无封面图时，用书名生成的占位封面（根据书名稳定取色）。
//

import SwiftUI

struct BookCoverView: View {
    let title: String

    private var palette: [Color] {
        [
            Color(red: 0.36, green: 0.42, blue: 0.62),
            Color(red: 0.58, green: 0.40, blue: 0.42),
            Color(red: 0.36, green: 0.52, blue: 0.48),
            Color(red: 0.50, green: 0.44, blue: 0.60),
            Color(red: 0.62, green: 0.50, blue: 0.34)
        ]
    }

    private var baseColor: Color {
        let hash = abs(title.hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [baseColor, baseColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack {
                Spacer()
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Spacer()
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
