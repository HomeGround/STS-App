import Flutter
import HaishinKit
import UIKit

/// Connects the Flutter Stream screen (lib/streaming/streamer.dart) to [Streamer]:
/// commands on the "sts/streamer" method channel, state changes on "sts/streamer/events",
/// and the camera preview as the "sts/camera-preview" platform view.
final class StreamerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  /// One per Stream screen visit: created by "start", released by "shutdown".
  @MainActor private var streamer: Streamer?
  private var eventSink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = StreamerPlugin()
    let messenger = registrar.messenger()
    registrar.addMethodCallDelegate(plugin, channel: FlutterMethodChannel(name: "sts/streamer", binaryMessenger: messenger))
    FlutterEventChannel(name: "sts/streamer/events", binaryMessenger: messenger).setStreamHandler(plugin)
    registrar.register(PreviewFactory(plugin: plugin), withId: "sts/camera-preview")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        result(try await self.perform(call))
      } catch {
        result(FlutterError(code: call.method, message: error.localizedDescription, details: nil))
      }
    }
  }

  @MainActor private func perform(_ call: FlutterMethodCall) async throws -> Any? {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      let streamer = self.streamer ?? Streamer()
      streamer.onEvent = { [weak self] event in self?.eventSink?(event) }
      self.streamer = streamer
      try await streamer.start(
        width: arguments["width"] as? Int ?? 1920,
        height: arguments["height"] as? Int ?? 1080,
        frameRate: arguments["fps"] as? Int ?? 30
      )
    case "setOverlay":
      if let png = arguments["png"] as? FlutterStandardTypedData {
        streamer?.setOverlay(png.data)
      }
    case "goLive":
      guard let text = arguments["url"] as? String, let url = URL(string: text) else {
        throw StreamerError("That stream address isn't valid.")
      }
      try await streamer?.goLive(to: url)
    case "stop":
      await streamer?.stop()
    case "shutdown":
      await streamer?.shutdown()
      streamer = nil
    default:
      return FlutterMethodNotImplemented
    }
    return nil
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  /// What is being streamed, as the viewers will see it: the camera with the ticker on top.
  fileprivate func makePreview() -> UIView {
    let view = MTHKView(frame: .zero)
    Task { @MainActor in
      guard let streamer = self.streamer else { return }
      await streamer.mixer.addOutput(view)
    }
    return view
  }
}

private final class PreviewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: StreamerPlugin?

  init(plugin: StreamerPlugin) {
    self.plugin = plugin
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    PreviewPlatformView(plugin?.makePreview() ?? UIView())
  }
}

private final class PreviewPlatformView: NSObject, FlutterPlatformView {
  private let preview: UIView

  init(_ preview: UIView) {
    self.preview = preview
  }

  func view() -> UIView {
    preview
  }
}
