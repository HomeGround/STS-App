import UIKit
import WebKit

/// Loads the web ticker page (ticker.homegroundapp.com/match/<ID>) in a hidden web view and hands snapshots
/// of it to the stream overlay. Adapted from the SportsStreaming app's Ticker.
///
/// Snapshotting the page is expensive and runs on the main thread, where HaishinKit's compositor clock also runs,
/// so every snapshot can delay a stream frame. The page therefore reports its own changes (DOM edits, CSS
/// animations and transitions), and frames are captured at the overlay frame rate only while something is
/// changing, plus a slow heartbeat as a safety net. A scoreboard that isn't changing costs almost nothing.
@MainActor
final class WebTicker: NSObject {
  /// Keep capturing for this long after the last change, so the end of a change is captured.
  private static let settleDuration: CFTimeInterval = 0.5
  /// Capture at least this often, even when the page reports no changes.
  private static let heartbeatInterval: CFTimeInterval = 1.0
  private static let changeMessageName = "tickerChanged"

  /// Injected into the page. Reports "animating" while a CSS animation or transition, canvas or video is running,
  /// and "still" otherwise, each time the page changes. Uses microtasks rather than timers, because WebKit
  /// slows timers down for pages that aren't on screen.
  private static let changeObserverScript = """
    (function () {
      if (window.__tickerChangeObserver) { return; }
      window.__tickerChangeObserver = true;
      function isAnimating() {
        if (document.querySelector('canvas, video')) { return true; }
        if (!document.getAnimations) { return false; }
        return document.getAnimations().some(function (a) { return a.playState === 'running'; });
      }
      function post(state) {
        try { window.webkit.messageHandlers.\(changeMessageName).postMessage(state); } catch (e) {}
      }
      var queued = false;
      function report() {
        if (queued) { return; }
        queued = true;
        queueMicrotask(function () {
          queued = false;
          post(isAnimating() ? 'animating' : 'still');
        });
      }
      new MutationObserver(report).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
      ['animationstart', 'transitionrun'].forEach(function (type) {
        document.addEventListener(type, function () { post('animating'); }, true);
      });
      ['animationend', 'animationcancel', 'transitionend', 'transitioncancel'].forEach(function (type) {
        document.addEventListener(type, report, true);
      });
      report();
    })();
    """

  private let webView: WKWebView
  private let renderer: UIGraphicsImageRenderer
  private let onFrame: (CGImage) -> Void
  private var displayLink: CADisplayLink?
  private var isLoaded = false
  private var targetFPS: Double = 15

  /// When the next frame is due. Pacing by time works on 60 Hz and 120 Hz screens alike. Zero means capture now.
  private var nextCaptureTime: CFTimeInterval = 0
  private var pageIsAnimating = false
  private var lastChangeTime: CFTimeInterval = 0
  private var lastCaptureTime: CFTimeInterval = 0

  /// - Parameters:
  ///   - pageSize: The size the page is laid out at, in points, so the ticker looks the same at any stream size.
  ///   - outputSize: The pixel size of the snapshots. Must match the stream canvas, since the compositor doesn't scale them.
  init(url: URL, pageSize: CGSize, outputSize: CGSize, onFrame: @escaping (CGImage) -> Void) {
    self.onFrame = onFrame
    let format = UIGraphicsImageRendererFormat()
    format.scale = outputSize.width / pageSize.width
    format.opaque = false
    renderer = UIGraphicsImageRenderer(size: pageSize, format: format)

    let configuration = WKWebViewConfiguration()
    configuration.userContentController.addUserScript(
      WKUserScript(source: Self.changeObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    webView = WKWebView(frame: CGRect(origin: .zero, size: pageSize), configuration: configuration)
    super.init()
    // A weak proxy, because the content controller keeps its message handlers alive.
    configuration.userContentController.add(WeakMessageHandler(self), name: Self.changeMessageName)

    // The page has a transparent background, so only the scoreboard covers the video.
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false
    webView.isUserInteractionEnabled = false
    webView.navigationDelegate = self
    // Render at the snapshot's scale rather than the screen's 3x, which would only be scaled down again.
    webView.contentScaleFactor = format.scale
    webView.load(URLRequest(url: url))
  }

  func start(fps: Double) {
    targetFPS = max(1, fps)
    guard displayLink == nil else { return }
    // A web view outside a window may stop drawing, which gives blank snapshots. It sits behind the
    // Flutter screen, which covers it completely.
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
      .first
    window?.insertSubview(webView, at: 0)

    nextCaptureTime = 0
    lastCaptureTime = 0
    lastChangeTime = CACurrentMediaTime()
    let link = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    print("[WebTicker] Capturing at up to \(Int(targetFPS)) FPS while the ticker changes")
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    webView.stopLoading()
    webView.removeFromSuperview()
  }

  fileprivate func pageDidChange(isAnimating: Bool) {
    pageIsAnimating = isAnimating
    lastChangeTime = CACurrentMediaTime()
  }

  @objc private func displayLinkFired(_ link: CADisplayLink) {
    guard isLoaded else { return }
    let now = link.timestamp
    let isChanging = pageIsAnimating || now - lastChangeTime < Self.settleDuration
    if isChanging {
      // Capture on a fixed 1/targetFPS schedule, whatever the screen's refresh rate. Half a refresh of slack
      // picks the nearest vsync, and advancing the schedule (rather than restarting it) keeps the average rate exact.
      let interval = 1.0 / targetFPS
      guard nextCaptureTime == 0 || now >= nextCaptureTime - link.duration / 2 else { return }
      // After a stall of more than one interval, restart the schedule instead of bursting to catch up.
      let isBehind = nextCaptureTime == 0 || now - nextCaptureTime > interval
      nextCaptureTime = isBehind ? now + interval : nextCaptureTime + interval
    } else {
      // Nothing is changing. Only the heartbeat captures, in case a change went unreported.
      guard now - lastCaptureTime >= Self.heartbeatInterval else { return }
      nextCaptureTime = 0
    }
    lastCaptureTime = now

    let image = renderer.image { _ in
      webView.drawHierarchy(in: webView.bounds, afterScreenUpdates: true)
    }
    if let cgImage = image.cgImage {
      onFrame(cgImage)
    }
  }
}

extension WebTicker: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isLoaded = true
    // Treat the freshly loaded page as a change, so it is captured straight away.
    lastChangeTime = CACurrentMediaTime()
    print("[WebTicker] Ticker page loaded")
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    print("[WebTicker] Ticker page failed: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    print("[WebTicker] Ticker page couldn't load: \(error.localizedDescription)")
  }
}

/// Forwards page-change messages to the ticker without keeping it alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var ticker: WebTicker?

  init(_ ticker: WebTicker) {
    self.ticker = ticker
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    let isAnimating = (message.body as? String) == "animating"
    MainActor.assumeIsolated { ticker?.pageDidChange(isAnimating: isAnimating) }
  }
}
