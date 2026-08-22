import Foundation
import AVFoundation
import MediaPlayer

/// Wraps `AVPlayer` for a single audio-chapter stream, mirroring `ReadAloudController`'s shape
/// (same `.playback` audio session category, same `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`
/// lock-screen wiring) since both are "play one linear audio thing with transport controls" --
/// no reason to invent a second pattern for what's structurally the same problem.
@MainActor
final class AudiobookPlayerController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackRate: Float = 1.0
    /// Live countdown for the sleep timer, in seconds; `nil` when no timer is running. Survives a
    /// chapter auto-advance (`stop()` followed by `play()` for the next chapter) on purpose -- a
    /// listener falling asleep across a chapter boundary is the whole point of this feature.
    @Published private(set) var sleepTimerRemainingSeconds: Int?

    /// Called when the current stream finishes playing on its own -- the view uses this to advance
    /// to the next chapter automatically, matching how listening to an audiobook naturally continues
    /// rather than stopping dead at every chapter boundary (unlike this app's text reader, which
    /// deliberately does *not* auto-continue past a chapter without a manual/scroll trigger).
    var onFinished: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var bookTitle = ""
    private var chapterTitle = ""
    private var sleepTimerTask: Task<Void, Never>?

    override init() {
        super.init()
        configureRemoteCommands()
    }

    func play(url: URL, bookTitle: String, chapterTitle: String) {
        activateAudioSession()
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidPlayToEnd), name: .AVPlayerItemDidPlayToEndTime, object: item
        )
        addTimeObserver()
        // `.rate = playbackRate` rather than `.play()` (which always resumes at 1.0x) -- AVPlayer
        // begins playing once the item is ready even if `rate` is set before loading finishes, so
        // this doesn't need to wait on item-ready status separately.
        newPlayer.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.rate = playbackRate
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    /// Pauses playback once `minutes` has elapsed; `sleepTimerRemainingSeconds` powers a live
    /// countdown in the UI. Starting a new timer while one is already running replaces it outright
    /// rather than stacking, matching every sleep-timer picker UI (including Legado's own).
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
            self.player?.pause()
            self.isPlaying = false
            self.sleepTimerRemainingSeconds = nil
            self.sleepTimerTask = nil
            self.updateNowPlayingInfo()
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemainingSeconds = nil
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 1))
        currentTime = seconds
        updateNowPlayingInfo()
    }

    func stop() {
        player?.pause()
        player = nil
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal -- matches ReadAloudController: playback just silently won't produce audio
            // if the session can't activate (e.g. another app holding an incompatible session).
        }
    }

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds, itemDuration.isFinite {
                    self.duration = itemDuration
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            if let self {
                self.player?.rate = self.playbackRate
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            self?.updateNowPlayingInfo()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyArtist: bookTitle
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    @objc nonisolated private func handleDidPlayToEnd() {
        Task { @MainActor in
            self.isPlaying = false
            self.onFinished?()
        }
    }
}
