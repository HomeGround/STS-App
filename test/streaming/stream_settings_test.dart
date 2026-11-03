import 'package:flutter_test/flutter_test.dart';
import 'package:sts/streaming/stream_settings.dart';

void main() {
  group('streamUrlFrom', () {
    test('sends a bare stream key to YouTube', () {
      expect(streamUrlFrom(' abcd-efgh-ijkl \n').url.toString(), 'rtmp://a.rtmp.youtube.com/live2/abcd-efgh-ijkl');
    });

    test('accepts a full rtmp or rtmps address with an app name and key', () {
      expect(streamUrlFrom('rtmps://live.example.com/app/key123').url.toString(), 'rtmps://live.example.com/app/key123');
      expect(streamUrlFrom('rtmp://a.rtmp.youtube.com/live2/abcd').url.toString(), 'rtmp://a.rtmp.youtube.com/live2/abcd');
    });

    test('repairs YouTube\'s Stream URL with the key pasted straight after it', () {
      expect(streamUrlFrom('rtmp://a.rtmp.youtube.com/live2abcd-efgh').url.toString(),
          'rtmp://a.rtmp.youtube.com/live2/abcd-efgh');
    });

    test('explains what is wrong', () {
      expect(streamUrlFrom('   ').problem, 'Enter your stream key.');
      expect(streamUrlFrom('rtmp://a.rtmp.youtube.com/live2').problem, contains("YouTube's Stream URL"));
      expect(streamUrlFrom('abc/def').problem, contains("doesn't look right"));
      expect(streamUrlFrom('rtmp://a.rtmp.youtube.com/live2').url, isNull);
    });
  });
}
