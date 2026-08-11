import SwiftUI
import UIKit

/// Thin wrapper around the system share sheet -- used where the content to share isn't ready
/// synchronously (e.g. assembling a txt export from async-fetched chapter cache), so a plain
/// `ShareLink` (which needs its item available the moment the view is built) doesn't fit.
/// Presenting this in `.sheet(isPresented:)` shows the share sheet immediately.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
