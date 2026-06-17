//
//  AudioPlayerView.swift
//  readBook
//
//  听书 UI：底部迷你控制栏与全屏控制面板。
//
//  ⚠️ 听书功能已暂停，见 BACKLOG.md。
//

#if false

import SwiftUI

struct AudioMiniBar: View {
    @Bindable var audioVM: AudioPlayerViewModel
    let theme: ReaderTheme

    var body: some View {
        Button { audioVM.showFullPanel = true } label: {
            VStack(spacing: 8) {
                Text(audioVM.currentSentenceText)
                    .font(.caption)
                    .foregroundStyle(theme.textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 28) {
                    controlIcon("backward.fill") { audioVM.previousSentence() }
                    controlIcon(audioVM.isPlaying ? "pause.fill" : "play.fill") {
                        audioVM.togglePlayPause()
                    }
                    .font(.title2)
                    controlIcon("forward.fill") { audioVM.nextSentence() }
                    Text(audioVM.rateDisplay)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryTextColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.backgroundColor.opacity(0.98))
            .overlay(alignment: .top) {
                Rectangle().fill(theme.secondaryTextColor.opacity(0.15)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func controlIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.body)
                .foregroundStyle(theme.textColor)
        }
        .buttonStyle(.plain)
    }
}

struct AudioFullPanel: View {
    @Bindable var audioVM: AudioPlayerViewModel
    let theme: ReaderTheme
    let chapterText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(audioVM.currentChapterTitle)
                    .font(.title2.bold())
                    .foregroundStyle(theme.textColor)
                    .padding(.top, 8)

                highlightedTextArea
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                progressSection
                    .padding(.horizontal, 20)

                controlGrid
                    .padding(.vertical, 16)

                rateSection
                    .padding(.horizontal, 20)

                voiceSection
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                sleepSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer(minLength: 0)
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("收起") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var highlightedTextArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(highlightedAttributedText)
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("highlight-block")
            }
            .onChange(of: audioVM.currentSentenceIndex) { _, _ in
                withAnimation { proxy.scrollTo("highlight-block", anchor: .center) }
            }
        }
        .frame(maxHeight: 280)
    }

    private var highlightedAttributedText: AttributedString {
        let sentence = audioVM.currentSentenceText
        var full = AttributedString(chapterText)
        full.foregroundColor = theme.textColor.opacity(0.45)
        if let range = full.range(of: sentence) {
            full[range].foregroundColor = theme.textColor
            full[range].font = .body.bold()
        }
        return full
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { audioVM.chapterProgress },
                set: { audioVM.seekProgress($0) }
            ), in: 0...1)
            .tint(theme.textColor)
        }
    }

    private var controlGrid: some View {
        HStack(spacing: 20) {
            largeControl("backward.end.fill", action: audioVM.previousChapter)
            largeControl("backward.fill", action: audioVM.previousSentence)
            Button(action: { audioVM.togglePlayPause() }) {
                Image(systemName: audioVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(theme.textColor)
            }
            largeControl("forward.fill", action: audioVM.nextSentence)
            largeControl("forward.end.fill", action: audioVM.nextChapter)
        }
    }

    private func largeControl(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.title2)
                .foregroundStyle(theme.textColor)
        }
    }

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("语速")
                    .foregroundStyle(theme.secondaryTextColor)
                Spacer()
                Text(audioVM.rateDisplay)
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: Binding(
                get: { Double(audioVM.rate) },
                set: { audioVM.rate = Float($0) }
            ), in: 0.5...3.0, step: 0.1)
            .tint(theme.textColor)
        }
    }

    private var voiceSection: some View {
        Picker("音色", selection: $audioVM.voiceGender) {
            ForEach(AudioVoiceGender.allCases) { g in
                Text(g.displayName).tag(g)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("睡眠定时")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryTextColor)
            Picker("睡眠定时", selection: $audioVM.sleepTimer) {
                ForEach(AudioSleepTimer.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.textColor)
        }
    }
}

#endif
