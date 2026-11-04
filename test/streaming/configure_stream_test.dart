import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sts/streaming/configure_stream.dart';
import 'package:sts/streaming/stream_settings.dart';
import 'package:sts/streaming/ticker_snapshot.dart';

import 'ticker_test.dart' show snapshotJson;

void main() {
  StreamSetup? opened;
  final looked = <String>[];

  Future<void> pumpScreen(WidgetTester tester, {Map<String, Object> saved = const {}, bool found = true}) async {
    SharedPreferences.setMockInitialValues(saved);
    opened = null;
    looked.clear();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ConfigureStreamScreen(
        lookupMatch: (id) async {
          looked.add(id);
          return found ? TickerSnapshot.fromJson(snapshotJson()) : null;
        },
        onOpen: (_, setup) => opened = setup,
      ),
    ));
    await tester.pump();
  }

  Finder matchIdField() => find.byType(TextField).at(0);
  Finder streamKeyField() => find.byType(TextField).at(1);

  Future<void> openCamera(WidgetTester tester) async {
    await tester.tap(find.text('Open camera'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('match IDs are typed in capitals, letters and digits only', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(matchIdField(), 'k7p2-qx ab');
    expect(tester.widget<TextField>(matchIdField()).controller!.text, 'K7P2QXAB');
  });

  testWidgets('opens the camera with the match, the YouTube address and the chosen quality', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(matchIdField(), 'K7P2QXAB');
    await tester.enterText(streamKeyField(), 'my-key');
    await tester.tap(find.text('720p'));
    await tester.tap(find.text('60 fps'));
    await tester.pump();
    await openCamera(tester);

    expect(looked, ['K7P2QXAB']);
    expect(opened!.match.id, 'K7P2QXAB');
    expect(opened!.url.toString(), 'rtmp://a.rtmp.youtube.com/live2/my-key');
    expect(opened!.quality, StreamQuality.hd720);
    expect(opened!.frameRate, 60);
    expect((await SharedPreferences.getInstance()).getString('stream_key'), 'my-key',
        reason: 'the key is remembered for next time');
  });

  testWidgets('fills in the stream key used last time', (tester) async {
    await pumpScreen(tester, saved: {'stream_key': 'saved-key'});
    expect(tester.widget<TextField>(streamKeyField()).controller!.text, 'saved-key');
  });

  testWidgets('says when no match has the ID', (tester) async {
    await pumpScreen(tester, found: false);
    await tester.enterText(matchIdField(), 'ZZZZZZZZ');
    await tester.enterText(streamKeyField(), 'my-key');
    await tester.pump();
    await openCamera(tester);
    expect(opened, isNull);
    expect(find.textContaining('No match has the ID ZZZZZZZZ.'), findsOneWidget);
  });

  testWidgets('says when the stream key is YouTube\'s server address instead', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(matchIdField(), 'K7P2QXAB');
    await tester.enterText(streamKeyField(), 'rtmp://a.rtmp.youtube.com/live2');
    await tester.pump();
    await openCamera(tester);
    expect(opened, isNull);
    expect(looked, isEmpty);
    expect(find.textContaining("YouTube's Stream URL"), findsOneWidget);
  });
}
