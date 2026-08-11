import SwiftUI
import UIKit

/// Wraps `UIPageViewController(transitionStyle: .pageCurl)` for the "仿真" style -- deliberately not
/// hand-rolled: a believable paper-curl needs a 3D-ish deformation iOS already implements natively
/// via this transition style, and reusing it means the interactive swipe-to-curl gesture is Apple's
/// own well-tested code rather than a custom gesture recognizer this project has no way to
/// interactively test before a real device sees it.
///
/// Chapter-boundary handling can't ride on `UIPageViewController`'s own swipe: when
/// `viewControllerBefore`/`viewControllerAfter` returns `nil` at an edge, the built-in gesture just
/// bounces back with no callback hook for "the user wanted to keep going." A `UITapGestureRecognizer`
/// added directly to the page view controller's own view (not a SwiftUI overlay layered on top,
/// which would intercept touches before the built-in pan/swipe recognizers ever saw them) fills that
/// gap and also drives the toggle-chrome/prev-page/next-page actions on a plain tap, matching the
/// other 3 non-scroll styles' zones (left 30% / middle 40% / right 30%).
struct PageCurlContainerView: UIViewControllerRepresentable {
    let pageCount: Int
    @Binding var currentPageIndex: Int
    let pageBuilder: (Int) -> AnyView
    let onTapMiddle: () -> Void
    let onRequestPreviousChapter: () -> Void
    let onRequestNextChapter: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: nil
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        if pageCount > 0 {
            let startIndex = min(max(currentPageIndex, 0), pageCount - 1)
            controller.setViewControllers(
                [context.coordinator.hostingController(for: startIndex)], direction: .forward, animated: false
            )
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        controller.view.addGestureRecognizer(tap)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard pageCount > 0, currentPageIndex >= 0, currentPageIndex < pageCount else { return }
        let visibleIndex = context.coordinator.currentIndex(in: controller)
        // Only drive the transition externally (a volume-key press, or this view's own tap
        // gesture) when the requested index disagrees with what's already on screen -- the user's
        // own swipe already updated `currentPageIndex` via the delegate callback below, and
        // re-issuing `setViewControllers` for that same page would restart Apple's own in-flight
        // curl animation instead of leaving it alone.
        guard visibleIndex != currentPageIndex else { return }
        let direction: UIPageViewController.NavigationDirection = currentPageIndex > visibleIndex ? .forward : .reverse
        controller.setViewControllers(
            [context.coordinator.hostingController(for: currentPageIndex)], direction: direction, animated: true
        )
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlContainerView

        init(_ parent: PageCurlContainerView) {
            self.parent = parent
        }

        func hostingController(for index: Int) -> UIViewController {
            let hosting = UIHostingController(rootView: parent.pageBuilder(index))
            hosting.view.tag = index
            hosting.view.backgroundColor = .clear
            return hosting
        }

        func currentIndex(in controller: UIPageViewController) -> Int {
            controller.viewControllers?.first?.view.tag ?? parent.currentPageIndex
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            let index = viewController.view.tag
            guard index > 0 else { return nil }
            return hostingController(for: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            let index = viewController.view.tag
            guard index < parent.pageCount - 1 else { return nil }
            return hostingController(for: index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let current = pageViewController.viewControllers?.first else { return }
            parent.currentPageIndex = current.view.tag
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let x = recognizer.location(in: view).x
            let width = view.bounds.width
            guard width > 0 else { return }
            if x < width * 0.3 {
                turnPage(direction: -1)
            } else if x > width * 0.7 {
                turnPage(direction: 1)
            } else {
                parent.onTapMiddle()
            }
        }

        private func turnPage(direction: Int) {
            let newIndex = parent.currentPageIndex + direction
            guard newIndex >= 0, newIndex < parent.pageCount else {
                if direction > 0 { parent.onRequestNextChapter() } else { parent.onRequestPreviousChapter() }
                return
            }
            parent.currentPageIndex = newIndex
        }
    }
}
