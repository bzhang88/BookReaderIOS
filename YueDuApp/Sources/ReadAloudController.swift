import Foundation
import AVFoundation
import MediaPlayer
import WebBookOrchestrator

/// Wraps `AVSpeechSynthesizer` for paragraph-by-paragraph read-aloud, one chapter's worth of
/// `paragraphs` at a time -- crossing into the next chapter is the *owner's* job (see
/// `onReachedEnd`), not something this controller knows how to do itself, since it has no concept
/// of "the book" beyond whatever flat paragraph array it was last given.
@MainActor
final class ReadAloudController: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentParagraphIndex = 0
    /// Real gap found comparing against Legado: `BaseReadAloudService.setTimer`/`addTimer` gives
    /// read-aloud its own sleep timer (with a notification button); this controller had none, unlike
    /// `AudiobookPlayerController`, which already implements exactly this pattern. `nil` when no
    /// timer is running.
    @Published private(set) var sleepTimerRemainingSeconds: Int?

    /// Called when speech naturally runs out of `paragraphs` (not when explicitly stopped via
    /// `stop()`/pausing) -- confirmed against Legado_Max's own `BaseReadAloudService.nextP()`/
    /// `nextChapter()` that real read-aloud continues across chapter boundaries automatically
    /// rather than stopping at every one. The *owner* decides what "continuing" means (usually:
    /// call `start(paragraphs:...)` again with the next chapter's text) and is responsible for
    /// calling `stop()` itself if it can't continue (e.g. this was the last chapter) -- this
    /// controller doesn't call `stop()` on its own once a handler is set, so a continuing owner
    /// never pays for a stop-then-immediately-restart audio session blip.
    var onReachedEnd: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var paragraphs: [String] = []
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var bookTitle = ""
    private var chapterTitle = ""
    private var sleepTimerTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureRemoteCommands()
    }

    /// `startIndex` lets the reader's long-press paragraph menu start speech from wherever was
    /// pressed ("朗读，从这里开始") instead of always the chapter's first paragraph -- clamped into
    /// bounds rather than trusted as-is, since a stale index (paragraphs re-split by a purify-rule
    /// change between when the menu was opened and tapped) is possible in principle.
    func start(paragraphs: [String], bookTitle: String, chapterTitle: String, startIndex: Int = 0) {
        activateAudioSession()
        self.paragraphs = paragraphs
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        currentParagraphIndex = paragraphs.indices.contains(startIndex) ? startIndex : 0
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

    /// Pauses read-aloud once `minutes` has elapsed; same pattern as
    /// `AudiobookPlayerController.startSleepTimer` (weak-self `Task` countdown, replaces rather than
    /// stacks a previous timer). Pauses (not `stop()`s) so resuming continues from the exact
    /// paragraph it left off at, matching what "pause" already means everywhere else in this
    /// controller.
    func startSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        sleepTimerRemainingSeconds = minutes * 60
        sleepTimerTask = Task { @MainActor [weak self] in
            while let self, let remaining = self.sleepTimerRemainingSeconds, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.sleepTimerRemainingSeconds = remaining - 1
            }
            guard let self, !Task.isCancelled else { return }
            if self.isSpeaking, !self.isPaused {
                self.synthesizer.pauseSpeaking(at: .word)
                self.isPaused = true
                self.updateNowPlayingInfo()
            }
            self.sleepTimerRemainingSeconds = nil
            self.sleepTimerTask = nil
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemainingSeconds = nil
    }

    private func speakCurrentParagraph() {
        guard paragraphs.indices.contains(currentParagraphIndex) else {
            stop()
            return
        }
        let paragraphText = paragraphs[currentParagraphIndex]
        // Real bug found comparing against Legado: this used to only skip a paragraph that's empty
        // after trimming whitespace -- a punctuation-only paragraph (e.g. a lone "——" scene-break
        // marker) isn't empty, so it used to get spoken as a raw-punctuation blip instead of cleanly
        // skipped. `ReadAloudTextFilter.isSpeakable` matches Legado's own `notReadAloudRegex`.
        guard ReadAloudTextFilter.isSpeakable(paragraphText) else {
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
        } else if let onReachedEnd {
            onReachedEnd()
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
