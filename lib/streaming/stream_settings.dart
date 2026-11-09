import 'ticker_snapshot.dart';

/// The size of the streamed video. The ticker is drawn at exactly this size.
enum StreamQuality {
  hd720(1280, 720, '720p'),
  hd1080(1920, 1080, '1080p');

  const StreamQuality(this.width, this.height, this.label);

  final int width;
  final int height;
  final String label;
}

/// Everything the Stream screen needs, chosen on the Configure Stream screen.
class StreamSetup {
  const StreamSetup({required this.match, required this.url, required this.quality, required this.frameRate});

  final TickerSnapshot match;

  /// Where to publish, such as `rtmp://a.rtmp.youtube.com/live2/<key>`.
  final Uri url;
  final StreamQuality quality;
  final int frameRate;
}

/// The web ticker page for a match. It follows the scorer's MQTT messages and is snapshotted onto the video.
Uri webTickerPage(String matchId) => Uri.parse('https://ticker.homegroundapp.com/match/$matchId');

/// A bare stream key is sent to YouTube's ingest server.
const youTubeIngestUrl = 'rtmp://a.rtmp.youtube.com/live2';

/// Turns what was typed in the stream key field into a publish URL, or says what's wrong with it.
///
/// Accepts a bare YouTube stream key, or a full rtmp:// or rtmps:// URL that ends in the key.
/// The URL's path needs at least an app name and a key, or the streaming library builds a broken address.
({Uri? url, String? problem}) streamUrlFrom(String input) {
  // Keys and URLs never contain whitespace, but pasted text often picks some up.
  final cleaned = input.replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return (url: null, problem: 'Enter your stream key.');
  const malformed = "That stream key doesn't look right. Copy it again from YouTube Studio.";
  final lowered = cleaned.toLowerCase();

  if (!lowered.startsWith('rtmp://') && !lowered.startsWith('rtmps://')) {
    // A bare key. Anything with a slash or colon is a mangled address, not a key.
    if (cleaned.contains('/') || cleaned.contains(':')) return (url: null, problem: malformed);
    return (url: Uri.parse('$youTubeIngestUrl/$cleaned'), problem: null);
  }

  final url = Uri.tryParse(cleaned);
  if (url == null || url.host.isEmpty) return (url: null, problem: malformed);
  final path = url.pathSegments.where((part) => part.isNotEmpty).toList();
  if (path.length >= 2) return (url: url, problem: null);
  // YouTube's Stream URL with the key pasted straight after it, such as ".../live2abcd-efgh". Put the slash back.
  if (path.length == 1 && path.single.toLowerCase().startsWith('live2') && path.single.length > 5) {
    return (url: url.replace(path: '/live2/${path.single.substring(5)}'), problem: null);
  }
  return (
    url: null,
    problem: path.length <= 1
        ? "That's YouTube's Stream URL, not the stream key. In YouTube Studio, copy the Stream key and paste it here."
        : malformed,
  );
}
