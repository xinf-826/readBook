//
//  ReaderSettingsView.swift
//  readBook
//
//  阅读设置面板：字号/行距/主题/字体/翻页动画/阅读模式/亮度。修改即时生效并持久化。
//

import SwiftUI

struct ReaderSettingsView: View {
    @Environment(BookStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("字号与行距") {
                    Stepper(value: $store.settings.fontSize, in: ReaderSettings.minFontSize...ReaderSettings.maxFontSize, step: 1) {
                        Text("字号 \(Int(store.settings.fontSize))pt")
                    }
                    HStack {
                        Text("行距")
                        Slider(value: $store.settings.lineSpacing, in: 0...20, step: 1)
                    }
                }

                Section("主题") {
                    Toggle("跟随系统", isOn: $store.settings.followSystem)

                    Picker("主题", selection: $store.settings.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.settings.followSystem)

                    HStack(spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            themeSwatch(theme)
                        }
                    }
                    .disabled(store.settings.followSystem)
                    .opacity(store.settings.followSystem ? 0.4 : 1)
                }

                Section("字体") {
                    Picker("字体", selection: $store.settings.font) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("阅读模式") {
                    Picker("阅读模式", selection: $store.settings.readingMode) {
                        ForEach(ReadingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("亮度") {
                    HStack {
                        Image(systemName: "sun.min")
                        Slider(value: $store.settings.brightness, in: 0.2...1.0)
                        Image(systemName: "sun.max")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.settings = .default
                    } label: {
                        Text("恢复默认设置")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func themeSwatch(_ theme: ReaderTheme) -> some View {
        let isSelected = store.settings.theme == theme
        return Circle()
            .fill(theme.backgroundColor)
            .frame(width: 32, height: 32)
            .overlay(
                Circle().stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                lineWidth: isSelected ? 3 : 1)
            )
            .overlay(
                Text("文").font(.caption2).foregroundStyle(theme.textColor)
            )
            .onTapGesture { store.settings.theme = theme }
            .accessibilityLabel(theme.displayName)
    }
}
