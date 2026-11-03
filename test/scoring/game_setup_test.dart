import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/onboarding/sport.dart';
import 'package:sts/scoring/game_setup.dart';
import 'package:sts/scoring/match_setup.dart';

void main() {
  GameSetup? next;

  Future<void> pumpScreen(WidgetTester tester) async {
    next = null;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: GameSetupScreen(sport: Sport.pickleball, onNext: (_, game) => next = game),
    ));
  }

  testWidgets('defaults to doubles, best of 3, game to 11', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Next'));
    expect(next!.sport, Sport.pickleball);
    expect(next!.format, MatchFormat.doubles);
    expect(next!.bestOf, 3);
    expect(next!.gameTo, 11);
  });

  testWidgets('passes on the chosen options', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Singles'));
    await tester.tap(find.text('Best of 1'));
    await tester.tap(find.text('21'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    expect(next!.format, MatchFormat.singles);
    expect(next!.bestOf, 1);
    expect(next!.gameTo, 21);
  });
}
