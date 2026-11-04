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
        fetchSnapshot: (_) async => match,
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

    // Leave the screen so its refresh timer stops.
    await tester.pumpWidget(const SizedBox());
  });
}
