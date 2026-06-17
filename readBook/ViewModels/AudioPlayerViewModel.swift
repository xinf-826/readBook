//
//  AudioPlayerViewModel.swift
//  readBook
//
//  听书状态：句子队列、播放控制、与 ReaderViewModel 进度同步。
//
//  ⚠️ 听书功能已暂停，见 BACKLOG.md。
//

#if false

import Foundation
import Observation
import UIKit

@Observable
final class AudioPlayerViewModel {
    private(set) var isActive = false
    private(set) var isPlaying = false
    private(set) var currentSentenceIndex = 0
    private(set) var sentences: [AudioSentence] = []
    private(set) var chapterProgress: Double = 0

    var rate: Float = 1.0 {
        didSet { player.setRateMultiplier(rate) }
    }
    var voiceGender: AudioVoiceGender = .female {
        didSet { player.setVoiceGender(voiceGender) }
    }
    var sleepTimer: AudioSleepTimer = .off {
        didSet { applySleepTimer() }
    }
    var showFullPanel = false

    var currentSentenceText: String {
        guard sentences.indices.contains(currentSentenceIndex) else { return "" }
        return sentences[currentSentenceIndex].text
    }

    var currentChapterTitle: String { readerVM.currentChapter.title }
    var rateDisplay: String { String(format: "%.1fx", rate) }

    private let readerVM: ReaderViewModel
    private let bookTitle: String
    private let player = AudioBookPlayer()
    private var remoteObservers: [NSObjectProtocol] = []

    init(readerVM: ReaderViewModel, bookTitle: String) {
        self.readerVM = readerVM
        self.bookTitle = bookTitle
        player.setRateMultiplier(rate)
        player.setVoiceGender(voiceGender)
        bindPlayerCallbacks()
        bindRemoteCommands()
    }

    func start() {
        if remoteObservers.isEmpty { bindRemoteCommands() }
        isActive = true
        reloadSentences(fromCurrentPosition: true)
        player.configureNowPlaying(title: bookTitle, chapter: currentChapterTitle)
        applySleepTimer()
        playCurrentSentence()
    }

    func stop() {
        for obs in remoteObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        remoteObservers.removeAll()
        player.stop()
        player.cancelSleepTimer()
        syncProgressToReader()
        isActive = false
        isPlaying = false
    }

    // MARK: - 播放控制

    func togglePlayPause() {
        if player.isPaused {
            player.resume()
            isPlaying = true
        } else if player.isSpeaking {
            player.pause()
            isPlaying = false
            syncProgressToReader()
        } else {
            playCurrentSentence()
        }
    }

    func previousSentence() {
        guard currentSentenceIndex > 0 else { return }
        currentSentenceIndex -= 1
        updateProgress()
        playCurrentSentence()
    }

    func nextSentence() {
        guard currentSentenceIndex + 1 < sentences.count else {
            advanceToNextChapter()
            return
        }
        currentSentenceIndex += 1
        updateProgress()
        playCurrentSentence()
    }

    func previousChapter() {
        guard readerVM.currentChapterIndex > 0 else { return }
        readerVM.goToChapter(readerVM.currentChapterIndex - 1)
        reloadSentences(fromCurrentPosition: false)
        currentSentenceIndex = 0
        updateProgress()
        refreshNowPlaying()
        playCurrentSentence()
    }

    func nextChapter() {
        guard readerVM.currentChapterIndex + 1 < readerVM.chapters.count else {
            player.stop()
            isPlaying = false
            syncProgressToReader()
            return
        }
        readerVM.goToChapter(readerVM.currentChapterIndex + 1)
        reloadSentences(fromCurrentPosition: false)
        currentSentenceIndex = 0
        updateProgress()
        refreshNowPlaying()
        playCurrentSentence()
    }

    func seekProgress(_ value: Double) {
        guard !sentences.isEmpty else { return }
        let idx = Int(value.clamped(to: 0...1) * Double(sentences.count - 1))
        currentSentenceIndex = idx
        updateProgress()
        syncProgressToReader()
        playCurrentSentence()
    }

    // MARK: - 内部

    private func bindPlayerCallbacks() {
        player.onUtteranceFinished = { [weak self] in
            Task { @MainActor in
                self?.handleSentenceFinished()
            }
        }
    }

    private func bindRemoteCommands() {
        let next = NotificationCenter.default.addObserver(
            forName: .audioPlayerNextSentence,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.nextSentence() }
        }
        let prev = NotificationCenter.default.addObserver(
            forName: .audioPlayerPreviousSentence,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.previousSentence() }
        }
        remoteObservers = [next, prev]
    }

    private func reloadSentences(fromCurrentPosition: Bool) {
        let chapterText = readerVM.chapterText(readerVM.currentChapterIndex)
        let offset = fromCurrentPosition ? readerVM.characterOffsetInChapter() : 0
        sentences = SentenceSegmenter.sentences(in: chapterText, fromOffset: offset)
        if fromCurrentPosition, !sentences.isEmpty {
            currentSentenceIndex = 0
        } else {
            currentSentenceIndex = 0
        }
        updateProgress()
    }

    private func playCurrentSentence() {
        guard sentences.indices.contains(currentSentenceIndex) else { return }
        let sentence = sentences[currentSentenceIndex]
        syncProgressToReader()
        refreshNowPlaying()
        player.speak(sentence.spokenText)
        isPlaying = true
    }

    private func handleSentenceFinished() {
        syncProgressToReader()
        if player.shouldStopAtChapterEnd,
           currentSentenceIndex >= sentences.count - 1 {
            player.stop()
            isPlaying = false
            sleepTimer = .off
            return
        }
        if currentSentenceIndex + 1 < sentences.count {
            currentSentenceIndex += 1
            updateProgress()
            playCurrentSentence()
        } else if readerVM.currentChapterIndex + 1 < readerVM.chapters.count {
            readerVM.goToChapter(readerVM.currentChapterIndex + 1)
            reloadSentences(fromCurrentPosition: false)
            refreshNowPlaying()
            playCurrentSentence()
        } else {
            isPlaying = false
            syncProgressToReader()
        }
    }

    private func advanceToNextChapter() {
        nextChapter()
    }

    private func updateProgress() {
        guard !sentences.isEmpty else {
            chapterProgress = 0
            return
        }
        chapterProgress = Double(currentSentenceIndex) / Double(max(1, sentences.count - 1))
    }

    private func syncProgressToReader() {
        guard sentences.indices.contains(currentSentenceIndex) else { return }
        let sentence = sentences[currentSentenceIndex]
        readerVM.applyReadingPosition(
            chapterIndex: readerVM.currentChapterIndex,
            characterOffset: sentence.startOffset
        )
        readerVM.persist()
    }

    private func refreshNowPlaying() {
        player.configureNowPlaying(title: bookTitle, chapter: currentChapterTitle)
    }

    private func applySleepTimer() {
        player.scheduleSleepTimer(sleepTimer) { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
    }
}

#endif