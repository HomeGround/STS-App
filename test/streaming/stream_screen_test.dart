import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/streaming/stream.dart';
import 'package:sts/streaming/stream_settings.dart';
import 'package:sts/streaming/ticker_snapshot.dart';

import 'ticker_test.dart' show snapshotJson;

void main() {
  testWidgets('the camera fills the screen, with Go live at the bottom', (tester) async {
    // Stands in for the native streamer: every command succeeds and no events arrive.
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('sts/streamer'), (_) async => null);
    messenger.setMockStreamHandler(
      const EventChannel('sts/streamer/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('sts/streamer'), null);
      messenger.setMockStreamHandler(const EventChannel('sts/streamer/events'), null);
    });

    const screen = Size(1600, 740);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final match = TickerSnapshot.fromJson(snapshotJson());
    await tester.pumpWidget(MaterialApp(
      home: StreamScreen(
        setup: StreamSetup(
          match: match,
          url: Uri.parse('rtmp://a.rtmp.youtube.com/live2/key'),
          quality: StreamQuality.hd720,
          frameRate: 30,
        ),
        watchMatch: (_) => const Stream.empty(),
      ),
    ));
    // Opening the camera draws the ticker, which needs real time to render.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();

    // Off iOS the camera area shows a notice, centred in the space the camera would fill.
    final preview = find.text('Streaming works on iPhone and iPad for now.');
    expect(tester.getCenter(preview).dy, closeTo(screen.height / 2, 1));
    expect(tester.getBottomLeft(find.text('Go live')).dy, greaterThan(screen.height - 100));
    expect(tester.getTopLeft(find.text('Smashers vs Wong / Khan   ·   K7P2QXAB')).dy, lessThan(60));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('redraws the ticker for newer scores from MQTT, and ignores older ones', (tester) async {
    var overlays = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('sts/streamer'), (call) async {
      if (call.method == 'setOverlay') overlays++;
      return null;
    });
    messenger.setMockStreamHandler(
      const EventChannel('sts/streamer/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('sts/streamer'), null);
      messenger.setMockStreamHandler(const EventChannel('sts/streamer/events'), null);
    });

    final updates = StreamController<TickerSnapshot>();
    addTearDown(updates.close);
    TickerSnapshot at(int version, List<int> score) => TickerSnapshot.fromJson(
      snapshotJson()
        ..['version'] = version
        ..['state'] = {'game': 2, 'games_won': [1, 0], 'score': score, 'serving_side': 1, 'call': '${score[0]}-0-1'},
    );
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }

    String? watched;
    await tester.pumpWidget(MaterialApp(
      home: StreamScreen(
        setup: StreamSetup(
          match: at(27, [2, 0]),
          url: Uri.parse('rtmp://a.rtmp.youtube.com/live2/key'),
          quality: StreamQuality.hd720,
          frameRate: 30,
        ),
        watchMatch: (id) {
          watched = id;
          return updates.stream;
        },
      ),
    ));
    await settle();
    expect(watched, 'K7P2QXAB');
    expect(overlays, 1, reason: 'the ticker is drawn once the camera opens');

    updates.add(at(27, [2, 0]));
    await settle();
    expect(overlays, 1, reason: 'the retained copy of the score already shown');

    updates.add(at(28, [3, 0]));
    await settle();
    expect(overlays, 2);

    updates.add(at(26, [1, 0]));
    await settle();
    expect(overlays, 2, reason: 'an older score never replaces a newer one');

    await tester.pumpWidget(const SizedBox());
  });
}
