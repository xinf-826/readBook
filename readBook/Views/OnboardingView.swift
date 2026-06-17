//
//  OnboardingView.swift
//  readBook
//
//  首次启动引导：说明如何获取并导入 .txt 文件。
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        VStack {
            TabView(selection: $page) {
                pageView(
                    icon: "books.vertical.fill",
                    title: "欢迎使用 readBook",
                    message: "一个简洁的本地小说阅读器。先把 .txt 小说传到手机，就能开始阅读。"
                )
                .tag(0)

                pageView(
                    icon: "square.and.arrow.down.fill",
                    title: "如何导入书籍",
                    message: "· 用电脑或其他设备通过 AirDrop 把 .txt 文件发到本机\n· 或先存入「文件」App\n\n然后在书架右上角点「+」选择文件即可导入。"
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 1 { withAnimation { page += 1 } } else { onFinish() }
            } label: {
                Text(page < 1 ? "下一步" : "开始使用")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func pageView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
