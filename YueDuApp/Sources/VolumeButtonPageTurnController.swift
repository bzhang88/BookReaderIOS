import UIKit
import AVFoundation
import MediaPlayer

/// Lets the hardware volume buttons page through a chapter while reading, matching Legado's own
/// `volumeKeyPage` behavior -- confirmed against `ReadBookActivity.onKeyDown/onKeyUp` handling
/// `KEYCODE_VOLUME_UP/DOWN`. iOS has no public API for "a volume button was pressed" (unlike
/// Android's key-event system), so this uses the standard technique other reading/camera apps rely
/// on: watch `AVAudioSession.outputVolume` via KVO, and the instant it moves away from a fixed
/// baseline, treat that as a button press, fire the page-turn callback, then silently snap the
/// system volume back to the baseline (via an offscreen `MPVolumeView`'s internal slider) so the
/// device's actual audio volume never visibly changes and the next press has room to register
/// again. This depends on `MPVolumeView`'s view hierarchy still containing a `UISlider` -- true
/// today, not a documented contract, so if a future iOS version changes that layout this silently
/// stops working rather than crashing (the reset becomes a no-op, worst case volume drifts).
/// Nothing about this can be verified by CI (no simulator has hardware volume buttons); it needs a
/// real device to confirm.
@MainActor
final class VolumeButtonPageTurnController: NSObject {
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var baselineVolume: Float = 0.5
    private var isResettingVolume = false
    private weak var hostView: UIView?
    private var volumeView: MPVolumeView?
    private var isObserving = false

    func start(in view: UIView) {
        guard !isObserving else { return }
        hostView = view
        try? session.setActive(true)
        baselineVolume = min(max(session.outputVolume, 0.1), 0.9)

        let hiddenVolumeView = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 40, height: 40))
        hiddenVolumeView.alpha = 0.0001
        view.addSubview(hiddenVolumeView)
        volumeView = hiddenVolumeView

        session.addObserver(self, forKeyPath: "outputVolume", options: [.new], context: nil)
        isObserving = true

        // The internal slider isn't guaranteed to exist until after this view has had a layout
        // pass -- a short delay before the first reset avoids silently no-op'ing on the very first
        // launch of the reader.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.applySystemVolume(self?.baselineVolume ?? 0.5)
        }
    }

    func stop() {
        guard isObserving else { return }
        session.removeObserver(self, forKeyPath: "outputVolume")
        isObserving = false
        volumeView?.removeFromSuperview()
        volumeView = nil
    }

    deinit {
        // `removeObserver` from a nonisolated deinit is safe here -- KVO de-registration doesn't
        // touch any of this class's @MainActor-isolated state, only AVAudioSession's own observer
        // list, and `stop()` (the normal path) already guards against double-removal via
        // `isObserving`; this is purely a safety net for a controller that's deallocated without
        // `stop()` ever having been called.
        if isObserving {
            session.removeObserver(self, forKeyPath: "outputVolume")
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "outputVolume" else { return }
        Task { @MainActor [weak self] in
            self?.handleVolumeChange(change?[.newKey] as? Float)
        }
    }

    private func handleVolumeChange(_ newVolume: Float?) {
        guard !isResettingVolume, let newVolume else { return }
        if newVolume > baselineVolume {
            onVolumeUp?()
        } else if newVolume < baselineVolume {
            onVolumeDown?()
        } else {
            return
        }
        isResettingVolume = true
        applySystemVolume(baselineVolume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isResettingVolume = false
        }
    }

    private func applySystemVolume(_ volume: Float) {
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = volume
    }
}
