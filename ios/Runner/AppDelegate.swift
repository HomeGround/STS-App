import Flutter
import UIKit

/// The app runs on scenes (Info.plist's UIApplicationSceneManifest, using FlutterSceneDelegate), which iOS
/// requires for apps built with the current SDK. The Flutter view is created with the scene, after launch,
/// so plugins are registered when Flutter asks for them rather than in didFinishLaunching.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterPluginRegistrant {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    pluginRegistrant = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    // The camera, ticker overlay and RTMP streaming in Runner/Streaming.
    if let registrar = registry.registrar(forPlugin: "StreamerPlugin") {
      StreamerPlugin.register(with: registrar)
    }
  }
}
