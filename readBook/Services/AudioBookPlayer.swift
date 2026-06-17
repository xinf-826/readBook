//
//  AudioBookPlayer.swift
//  readBook
//
//  AVSpeechSynthesizer 封装：单句朗读、锁屏控制、后台播放与中断恢复。
//
//  ⚠️ 听书功能已暂停，见项目根目录 BACKLOG.md。恢复时将下方 #if false 改为 #if true。
//

#if false

import AVFoundation
import MediaPlayer
import UIKit

enum AudioVoiceGender: String, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: "普通话女声"
        case .male: "普通话男声"
        }
    }
}

enum AudioSleepTimer: String, CaseIterable, Identifiable {
    case off
    case minutes15
    case minutes30
    case minutes60
    case endOfChapter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "关闭"
        case .minutes15: "15 分钟"
        case .minutes30: "30 分钟"
        case .minutes60: "60 分钟"
        case .endOfChapter: "本章结束"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .off, .endOfChapter: nil
        case .minutes15: 15 * 60
        case .minutes30: 30 * 60
        case .minutes60: 60 * 60
        }
    }
}

@MainActor
final class AudioBookPlayer: NSObject {
    var onUtteranceFinished: (() -> Void)?
    var onUtteranceStarted: ((String) -> Void)?

    private(set) var isSpeaking = false
    private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtteranceText = ""
    private var rateMultiplier: Float = 1.0
    private var voiceGender: AudioVoiceGender = .female
    private var sleepTimer: Timer?
    private var sleepMode: AudioSleepTimer = .off
    private var nowPlayingTitle = ""
    private var nowPlayingChapter = ""
    private var remoteCommandsConfigured = false

    override init() {
        super.init()
        synthesizer.delegate = self
        observeInterruptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        sleepTimer?.invalidate()
    }

    // MARK: - 播放控制

    func speak(_ text: String) {
        guard !text.isEmpty else {
            onUtteranceFinished?()
            return
        }
        stopInternal(clearDelegateCallback: false)
        configureAudioSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveVoice()
        let base = AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = Float((Double(base) * Double(rateMultiplier)).clamped(to: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)))
        utterance.pitchMultiplier = 1.0
        currentUtteranceText = text
        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
        updateNowPlaying(isPlaying: true)
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        updateNowPlaying(isPlaying: false)
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
        updateNowPlaying(isPlaying: true)
    }

    func togglePlayPause() {
        if isPaused {
            resume()
        } else if isSpeaking {
            pause()
        }
    }

    func stop() {
        stopInternal(clearDelegateCallback: true)
        updateNowPlaying(isPlaying: false)
    }

    private func stopInternal(clearDelegateCallback: Bool) {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isPaused = false
        currentUtteranceText = ""
        if clearDelegateCallback { onUtteranceFinished = nil }
    }

    // MARK: - 设置

    func setRateMultiplier(_ value: Float) {
        rateMultiplier = Float(Double(value).clamped(to: 0.5...3.0))
    }

    func setVoiceGender(_ gender: AudioVoiceGender) {
        voiceGender = gender
    }

    func configureNowPlaying(title: String, chapter: String) {
        nowPlayingTitle = title
        nowPlayingChapter = chapter
        setupRemoteCommandsIfNeeded()
        updateNowPlaying(isPlaying: isSpeaking && !isPaused)
    }

    func scheduleSleepTimer(_ mode: AudioSleepTimer, onFire: @escaping () -> Void) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepMode = mode
        guard let duration = mode.duration else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
                onFire()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepMode = .off
    }

    var shouldStopAtChapterEnd: Bool { sleepMode == .endOfChapter }

    // MARK: - 音频会话

    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[AudioBook] session error: \(error)")
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                self.handleInterruption(note)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    // MARK: - 锁屏 / 控制中心

    private func setupRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return MPRemoteCommandHandlerStatus.success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return MPRemoteCommandHandlerStatus.success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return MPRemoteCommandHandlerStatus.success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .audioPlayerNextSentence, object: self)
            }
            return MPRemoteCommandHandlerStatus.success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .audioPlayerPreviousSentence, object: self)
            }
            return MPRemoteCommandHandlerStatus.success
        }
    }

    private func updateNowPlaying(isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyAlbumTitle: nowPlayingChapter,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if isPlaying {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        let zhVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
        let preferredIDs: [String]
        switch voiceGender {
        case .female:
            preferredIDs = ["com.apple.voice.compact.zh-CN.Tingting", "com.apple.ttsbundle.Ting-Ting-compact"]
        case .male:
            preferredIDs = ["com.apple.voice.compact.zh-CN.Yu-shu", "com.apple.ttsbundle.Yu-shu-compact"]
        }
        for id in preferredIDs {
            if let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
        }
        let fallback = zhVoices.first { voice in
            switch voiceGender {
            case .female: return voice.name.localizedCaseInsensitiveContains("ting") || voice.gender == .female
            case .male: return voice.name.localizedCaseInsensitiveContains("shu") || voice.gender == .male
            }
        }
        return fallback ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }
}

extension AudioBookPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        Task { @MainActor in
            self.onUtteranceStarted?(text)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.onUtteranceFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }
}

extension Notification.Name {
    static let audioPlayerNextSentence = Notification.Name("audioPlayerNextSentence")
    static let audioPlayerPreviousSentence = Notification.Name("audioPlayerPreviousSentence")
}

#endif