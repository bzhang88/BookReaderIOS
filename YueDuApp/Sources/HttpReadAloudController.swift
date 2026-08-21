import Foundation
import AVFoundation
import MediaPlayer
import BookSourceModel
import Persistence

/// A cloud-TTS alternative to `ReadAloudController`'s `AVSpeechSynthesizer` -- fetches each
/// paragraph's audio from a user-configured `HttpTTSEngine`, caching through `HttpTTSCache` so
/// replaying (or re-reading past chapters) doesn't keep re-hitting the API. Structurally similar to
/// `ReadAloudController` (same paragraph-by-paragraph advance, same lock-screen wiring) but built
/// separately rather than generalized into one shared controller -- the two have genuinely
/// different playback primitives (`AVSpeechSynthesizer` utterances vs `AVPlayer` playing fetched
/// audio files), and forcing them through one abstraction right now would cost more clarity than
/// the duplication does.
@MainActor
final class HttpReadAloudController: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentParagraphIndex = 0
    @Published private(set) var errorMessage: String?

    /// Same contract as `ReadAloudController.onReachedEnd` -- see its doc comment.
    var onReachedEnd: (() -> Void)?

    // Set fresh on every `start()` rather than injected at construction -- this controller is a
    // plain `@StateObject` in `ReaderView`, constructed in a context (a property initializer) that
    // has no access to `@EnvironmentObject`-provided dependencies like `AppEnvironment.httpTTSCache`.
    private var cache: HttpTTSCache?
    private var player: AVPlayer?
    private var paragraphs: [String] = []
    private var engine: HttpTTSEngine?
    private var bookTitle = ""
    private var chapterTitle = ""
    private var fetchTask: Task<Void, Never>?

    override init() {
        super.init()
        configureRemoteCommands()
    }

    func start(paragraphs: [String], engine: HttpTTSEngine, cache: HttpTTSCache, bookTitle: String, chapterTitle: String) {
        activateAudioSession()
        self.paragraphs = paragraphs
        self.engine = engine
        self.cache = cache
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        currentParagraphIndex = 0
        errorMessage = nil
        speakCurrentParagraph()
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        isSpeaking = false
        isPaused = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePause() {
        guard let player else { return }
        if isPaused {
            player.play()
            isPaused = false
        } else {
            player.pause()
            isPaused = true
        }
        updateNowPlayingInfo()
    }

    func nextParagraph() {
        guard currentParagraphIndex < paragraphs.count - 1 else { return }
        currentParagraphIndex += 1
        speakCurrentParagraph()
    }

    func previousParagraph() {
        guard currentParagraphIndex > 0 else { return }
        currentParagraphIndex -= 1
        speakCurrentParagraph()
    }

    private func speakCurrentParagraph() {
        fetchTask?.cancel()
        guard let engine, paragraphs.indices.contains(currentParagraphIndex) else {
            stop()
            return
        }
        let text = paragraphs[currentParagraphIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            advanceToNextParagraphOrStop()
            return
        }
        fetchTask = Task {
            let url = await resolvedAudioURL(engine: engine, text: text)
            guard !Task.isCancelled else { return }
            guard let url else {
                errorMessage = "朗读引擎地址无效"
                stop()
                return
            }
            play(url: url)
        }
    }

    /// Cache-first: a hit returns a local file URL immediately; a miss downloads the raw audio
    /// bytes (via plain `URLSession`, not this app's `HTTPClient` abstraction -- that protocol
    /// returns text bodies for scraping, not binary audio) and writes them into the cache before
    /// handing back the now-cached local file's URL, so listening naturally populates the cache
    /// rather than needing a separate explicit "pre-download" step.
    private func resolvedAudioURL(engine: HttpTTSEngine, text: String) async -> URL? {
        guard let cache else { return nil }
        if let cached = await cache.cachedFileURL(engineID: engine.id, text: text) {
            return cached
        }
        guard let remoteURL = engine.url(forText: text) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: remoteURL),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return remoteURL
        }
        return try? await cache.store(engineID: engine.id, text: text, audio: data)
    }

    private func play(url: URL) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidPlayToEnd), name: .AVPlayerItemDidPlayToEndTime, object: item
        )
        newPlayer.play()
        isSpeaking = true
        isPaused = false
        updateNowPlayingInfo()
    }

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
            // Non-fatal, matches ReadAloudController/AudiobookPlayerController's own handling.
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

    @objc nonisolated private func handleDidPlayToEnd() {
        Task { @MainActor in
            self.advanceToNextParagraphOrStop()
        }
    }
}
