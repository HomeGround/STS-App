import 'package:flutter/services.dart';

import 'stream_settings.dart';

/// A change reported by the native streamer, such as going live or being disconnected.
typedef StreamerEvent = ({String state, String? error});

/// Talks to the native streaming engine in ios/Runner/Streaming: the camera, the ticker overlay and RTMP.
class Streamer {
  const Streamer();

  static const _channel = MethodChannel('sts/streamer');
  static const _events = EventChannel('sts/streamer/events');

  /// The native view showing what is being streamed: the camera with the ticker on top.
  static const previewViewType = 'sts/camera-preview';

  /// `state` is `idle`, `connecting`, `live` or `stopping`. `error` explains an unexpected disconnect.
  Stream<StreamerEvent> get events => _events.receiveBroadcastStream().map((event) {
    final map = event as Map;
    return (state: map['state'] as String, error: map['error'] as String?);
  });

  /// Opens the camera and microphone and sets the video size. Throws [PlatformException] if they can't be used.
  Future<void> start(StreamQuality quality, {required int frameRate}) =>
      _channel.invokeMethod('start', {'width': quality.width, 'height': quality.height, 'fps': frameRate});

  /// Replaces the ticker drawn over the video. [png] must be exactly the stream's size.
  Future<void> setOverlay(Uint8List png) => _channel.invokeMethod('setOverlay', {'png': png});

  /// Throws [PlatformException] with a message the person streaming can act on.
  Future<void> goLive(Uri url) => _channel.invokeMethod('goLive', {'url': url.toString()});

  Future<void> stop() => _channel.invokeMethod('stop');

  /// Ends any stream and releases the camera and microphone.
  Future<void> shutdown() => _channel.invokeMethod('shutdown');
}
