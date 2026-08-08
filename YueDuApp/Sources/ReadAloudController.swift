import Foundation
import AVFoundation
import MediaPlayer

/// Wraps `AVSpeechSynthesizer` for paragraph-by-paragraph read-aloud within the *current* chapter
/// -- cross-chapter auto-continue is a later increment, not this one, to keep the first version
/// well-scoped: this only has to get single-chapter playback, pause/resume, and lock-screen
/// transport controls right.
@MainActor
final class ReadAloudController: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentParagraphIndex = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var paragraphs: [String] = []
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var bookTitle = ""
    private var chapterTitle = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        configureRemoteCommands()
    }

    func start(paragraphs: [String], bookTitle: String, chapterTitle: String) {
        activateAudioSession()
        self.paragraphs = paragraphs
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        currentParagraphIndex = 0
        synthesizer.stopSpeaking(at: .immediate)
        speakCurrentParagraph()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePause() {
        guard isSpeaking else { return }
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        } else {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
        updateNowPlayingInfo()
    }

    func nextParagraph() {
        guard currentParagraphIndex < paragraphs.count - 1 else { return }
        currentParagraphIndex += 1
        synthesizer.stopSpeaking(at: .immediate)
        speakCurrentParagraph()
    }

    func previousParagraph() {
        guard currentParagraphIndex > 0 else { return }
        currentParagraphIndex -= 1
        synthesizer.stopSpeaking(at: .immediate)
        speakCurrentParagraph()
    }

    func setRate(_ newRate: Float) {
        rate = newRate
    }

    private func speakCurrentParagraph() {
        guard paragraphs.indices.contains(currentParagraphIndex) else {
            stop()
            return
        }
        let paragraphText = paragraphs[currentParagraphIndex]
        guard !paragraphText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            advanceToNextParagraphOrStop()
            return
        }
        let utterance = AVSpeechUtterance(string: paragraphText)
        utterance.rate = rate
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
        updateNowPlayingInfo()
    }

    /// Called both when a real utterance finishes speaking and when a blank line (paragraph
    /// splitting on chapter text produces some) needs skipping without counting as an utterance.
    private func advanceToNextParagraphOrStop() {
        if currentParagraphIndex < paragraphs.count - 1 {
            currentParagraphIndex += 1
            speakCurrentParagraph()
        } else {
            stop()
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal -- read-aloud just silently won't produce audio if the session can't
            // activate (e.g. another app holding an incompatible audio session).
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.togglePause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextParagraph()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousParagraph()
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyArtist: bookTitle
        ]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.advanceToNextParagraphOrStop()
        }
    }
}
