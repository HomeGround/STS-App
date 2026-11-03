import AVFoundation
import HaishinKit
import RTMPHaishinKit
import UIKit
import VideoToolbox

/// An error whose message is shown to the person streaming.
struct StreamerError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// The camera, the ticker overlay and RTMP publishing for the Stream screen.
/// Adapted from the SportsStreaming app's PushRTMP. Flutter drives it through StreamerPlugin.
///
/// The stream canvas has two layers: the back camera, and on top of it the ticker image that Flutter draws
/// whenever the score changes. Both are composited on the GPU and encoded as H.264.
@MainActor
final class Streamer {
  enum State: String {
    case idle, connecting, live, stopping
  }

  /// Reports state changes to Flutter, such as `["state": "live"]`, or `["state": "idle", "error": "..."]`.
  var onEvent: ([String: Any]) -> Void = { _ in }

  let mixer = MediaMixer()
  private(set) var state = State.idle
  private var session: (any Session)?
  private var sessionTask: Task<Void, Never>?
  @ScreenActor private var videoTrack: VideoTrackScreenObject?
  @ScreenActor private var overlay: ImageScreenObject?
  private var isStarted = false
  private var canvasSize = CGSize(width: 1920, height: 1080)
  private var frameRate = 30
  private static var isRTMPRegistered = false

  /// Opens the camera and microphone and sets up the canvas. Safe to call again to change the size or frame rate.
  func start(width: Int, height: Int, frameRate: Int) async throws {
    canvasSize = CGSize(width: width, height: height)
    self.frameRate = frameRate
    if isStarted {
      await applyFrameRate()
      await applyCanvasSize()
      return
    }

    let canFilm = await AVCaptureDevice.requestAccess(for: .video)
    let canRecord = await AVCaptureDevice.requestAccess(for: .audio)
    guard canFilm, canRecord else {
      throw StreamerError("Allow camera and microphone access for STS in the Settings app, then try again.")
    }

    if !Self.isRTMPRegistered {
      await SessionBuilderFactory.shared.register(RTMPSessionFactory())
      Self.isRTMPRegistered = true
    }

    var mixerSettings = await mixer.videoMixerSettings
    mixerSettings.mode = .offscreen
    await mixer.setVideoMixerSettings(mixerSettings)
    do {
      try await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), track: 0)
      try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
    } catch {
      throw StreamerError("Couldn't open the camera or microphone. Close other apps that might be using them and try again.")
    }
    await mixer.startRunning()
    await applyFrameRate()
    applyOrientation()

    try await Task { @ScreenActor in
      // Composite on the GPU. HaishinKit's default CPU compositor can't keep a steady frame rate with a
      // full-frame overlay. HaishinKit 2.2 marks this flag deprecated but has no replacement yet.
      await self.mixer.screen.isGPURendererEnabled = true
      await self.mixer.screen.backgroundColor = UIColor.black.cgColor

      let videoTrack = VideoTrackScreenObject()
      videoTrack.horizontalAlignment = .center
      videoTrack.verticalAlignment = .middle
      try await self.mixer.screen.addChild(videoTrack)
      self.videoTrack = videoTrack

      let overlay = ImageScreenObject()
      overlay.horizontalAlignment = .center
      overlay.verticalAlignment = .bottom
      try await self.mixer.screen.addChild(overlay)
      self.overlay = overlay
    }.value
    await applyCanvasSize()
    isStarted = true
  }

  /// Replaces the ticker. The PNG must be the canvas size, since the compositor doesn't scale it.
  func setOverlay(_ png: Data) {
    guard let image = UIImage(data: png)?.cgImage else { return }
    Task { @ScreenActor in
      self.overlay?.cgImage = image
    }
  }

  func goLive(to url: URL) async throws {
    guard state == .idle else { return }
    setState(.connecting)
    do {
      try await openSession(to: url)
      setState(.live)
    } catch {
      await tearDownSession()
      setState(.idle)
      throw StreamerError(Self.message(for: error))
    }
  }

  func stop() async {
    guard state == .live else { return }
    setState(.stopping)
    await tearDownSession()
    setState(.idle)
  }

  /// Ends any stream and releases the camera and microphone.
  func shutdown() async {
    await tearDownSession()
    state = .idle
    guard isStarted else { return }
    isStarted = false
    await mixer.stopRunning()
    try? await mixer.attachAudio(nil)
    try? await mixer.attachVideo(nil, track: 0)
  }

  // MARK: - Session

  private func openSession(to url: URL) async throws {
    guard let newSession = try await SessionBuilderFactory.shared.make(url).setMode(.publish).build() else {
      throw URLError(.unsupportedURL)
    }
    let bitRate = Self.videoBitRate(height: Int(canvasSize.height), frameRate: frameRate)
    try await newSession.stream.setVideoSettings(VideoCodecSettings(
      videoSize: canvasSize,
      bitRate: bitRate,
      // High profile compresses fast motion far better than HaishinKit's default, Baseline 3.1.
      profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
      // A keyframe every 2 seconds, as YouTube recommends.
      maxKeyFrameIntervalDuration: 2,
      expectedFrameRate: Double(frameRate)
    ))
    // Lowers the bitrate when the upload can't keep up, instead of letting video pile up until the stream freezes.
    await newSession.stream.setBitRateStrategy(StreamVideoAdaptiveBitRateStrategy(mamimumVideoBitrate: bitRate))
    try await newSession.stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000, format: .aac))
    await mixer.addOutput(newSession.stream)
    session = newSession
    sessionTask = Task {
      for await readyState in await newSession.readyState {
        // Keep the screen awake while streaming.
        UIApplication.shared.isIdleTimerDisabled = readyState == .open
      }
    }
    try await newSession.connect { [weak self] in
      Task { @MainActor in self?.handleDisconnect() }
    }
  }

  /// Called when the server or network drops a live stream after HaishinKit's own retries are used up.
  private func handleDisconnect() {
    guard state == .live else { return }
    Task {
      await tearDownSession()
      setState(.idle, error: "The stream was disconnected. Check your network, then go live again.")
    }
  }

  /// Closes the session and detaches it from the mixer, so a later session doesn't encode twice.
  private func tearDownSession() async {
    sessionTask?.cancel()
    sessionTask = nil
    guard let session else { return }
    self.session = nil
    // Stop feeding video and sound first, so nothing more is sent while the connection says goodbye.
    await mixer.removeOutput(session.stream)
    try? await session.close()
    UIApplication.shared.isIdleTimerDisabled = false
  }

  private func setState(_ newState: State, error: String? = nil) {
    state = newState
    var event: [String: Any] = ["state": newState.rawValue]
    if let error { event["error"] = error }
    onEvent(event)
  }

  // MARK: - Canvas

  private func applyCanvasSize() async {
    let size = canvasSize
    await Task { @ScreenActor in
      await self.mixer.screen.size = size
      self.videoTrack?.size = size
      self.overlay?.size = size
    }.value
  }

  /// Sets both the camera's capture rate and the rate the composited stream is rendered at.
  private func applyFrameRate() async {
    let rate = Double(frameRate)
    try? await mixer.setFrameRate(rate)
    try? await mixer.configuration(video: 0) { video in
      try video.setFrameRate(rate)
    }
  }

  /// The canvas is always 16:9 landscape, so the camera must deliver landscape frames the right way up.
  private func applyOrientation() {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let orientation: UIInterfaceOrientation?
    if #available(iOS 16.0, *) {
      orientation = scene?.effectiveGeometry.interfaceOrientation
    } else {
      orientation = scene?.interfaceOrientation
    }
    // Anything but landscape left (including not knowing yet, while the screen rotates) means landscape right,
    // which is where the Stream screen settles.
    let videoOrientation: AVCaptureVideoOrientation = orientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
    Task {
      await mixer.setVideoOrientation(videoOrientation)
    }
  }

  // MARK: - Helpers

  /// The top of YouTube's recommended H.264 range: fast sports motion needs the bits to avoid blocky frames.
  private static func videoBitRate(height: Int, frameRate: Int) -> Int {
    switch (height >= 1080, frameRate > 30) {
    case (true, true): return 9_000_000
    case (true, false): return 6_000_000
    case (false, true): return 6_000_000
    case (false, false): return 4_000_000
    }
  }

  /// Turns a connection error into advice the person streaming can act on. The raw error goes to the log.
  private static func message(for error: Error) -> String {
    print("[Streamer] Unable to go live: \(error)")
    switch error {
    case RTMPConnection.Error.invalidState, RTMPStream.Error.invalidState:
      // YouTube hangs up on a stream key it won't accept, which hides the real reason behind this error.
      return "YouTube closed the connection. The stream key is probably wrong, expired, or in use on another device. Copy the current key from YouTube Studio and try again."
    case RTMPConnection.Error.connectionTimedOut, RTMPConnection.Error.socketErrorOccurred:
      return "Couldn't reach the stream server. Check that the phone is online. Some Wi-Fi networks block live streaming, so try mobile data if it keeps failing."
    case RTMPConnection.Error.requestTimedOut, RTMPStream.Error.requestTimedOut:
      return "The stream server didn't answer in time. Check your connection and try again."
    case RTMPConnection.Error.requestFailed, RTMPStream.Error.requestFailed:
      return "The stream server refused the stream. Check the stream key."
    case RTMPConnection.Error.unsupportedCommand, is URLError:
      return "That stream address isn't supported. Enter the stream key on its own, or a full rtmp:// or rtmps:// address."
    default:
      return "Couldn't start the stream. Check the stream key and your connection, then try again."
    }
  }
}
