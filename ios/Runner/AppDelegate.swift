import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // The camera, ticker overlay and RTMP streaming in Runner/Streaming.
    StreamerPlugin.register(with: registrar(forPlugin: "StreamerPlugin")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
