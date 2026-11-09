import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/streaming/stream.dart';
import 'package:sts/streaming/stream_settings.dart';
import 'package:sts/streaming/ticker_snapshot.dart';

import 'ticker_test.dart' show snapshotJson;

void main() {
  /// Commands the screen sent to the native streamer, in order.
  late List<MethodCall> commands;

  Future<void> pumpScreen(WidgetTester tester, Size screen) async {
    commands = [];
    // Stands in for the native streamer: every command succeeds and no events arrive.
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('sts/streamer'), (call) async {
      commands.add(call);
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

    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: StreamScreen(
        setup: StreamSetup(
          match: TickerSnapshot.fromJson(snapshotJson()),
          url: Uri.parse('rtmp://a.rtmp.youtube.com/live2/key'),
          quality: StreamQuality.hd720,
          frameRate: 30,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('opens the camera, then shows this match\'s web ticker over the video', (tester) async {
    await pumpScreen(tester, const Size(1600, 740));
    expect(commands.map((c) => c.method), ['start', 'showWebTicker']);
    expect(commands[0].arguments, {'width': 1280, 'height': 720, 'fps': 30});
    expect(commands[1].arguments, {'url': 'https://ticker.homegroundapp.com/match/K7P2QXAB', 'fps': 15});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the camera fills the screen, with Go live at the bottom', (tester) async {
    const screen = Size(1600, 740);
    await pumpScreen(tester, screen);

    // Off iOS the camera area shows a notice, centred in the space the camera would fill.
    final preview = find.text('Streaming works on iPhone and iPad for now.');
    expect(tester.getCenter(preview).dy, closeTo(screen.height / 2, 1));
    expect(tester.getBottomLeft(find.text('Go live')).dy, greaterThan(screen.height - 100));
    expect(tester.getTopLeft(find.text('Smashers vs Wong / Khan   ·   K7P2QXAB')).dy, lessThan(60));
    await tester.pumpWidget(const SizedBox());
  });
}
