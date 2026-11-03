import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/onboarding/sport.dart';
import 'package:sts/scoring/match_setup.dart';
import 'package:sts/scoring/team_details.dart';

void main() {
  MatchSetup? started;
  List<SideSetup>? savedSides;

  /// [createGame] stands in for the database. By default it accepts the match and returns ID `K7P2QXAB` and a scorer token.
  Future<void> pumpScreen(
    WidgetTester tester,
    MatchFormat format, {
    Future<CreatedGame> Function(GameSetup game, List<SideSetup> sides)? createGame,
  }) async {
    started = null;
    savedSides = null;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: TeamDetailsScreen(
        game: GameSetup(sport: Sport.pickleball, format: format, bestOf: 3, gameTo: 11),
        createGame: createGame ??
            (game, sides) async {
              savedSides = sides;
              return (id: 'K7P2QXAB', scorerToken: 'secret-token');
            },
        onStart: (_, match) => started = match,
      ),
    ));
  }

  Future<void> startMatch(WidgetTester tester) async {
    await tester.tap(find.text('Start Match'));
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester, String label, int index, String text) async {
    await tester.enterText(find.widgetWithText(TextField, label).at(index), text);
    await tester.pump();
  }

  /// Fills every name field in order: side 1's players, then side 2's.
  Future<void> enterPlayers(WidgetTester tester, List<(String, String)> names) async {
    for (final (i, (first, last)) in names.indexed) {
      await enter(tester, 'First name', i, first);
      await enter(tester, 'Last name', i, last);
    }
  }

  bool startEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Match')).onPressed != null;

  testWidgets('doubles asks for a team name and two players per side', (tester) async {
    await pumpScreen(tester, MatchFormat.doubles);
    expect(find.widgetWithText(TextField, 'Team name (optional)'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'First name'), findsNWidgets(4));
    expect(find.widgetWithText(TextField, 'Last name'), findsNWidgets(4));
  });

  testWidgets('puts side 2 beside side 1', (tester) async {
    await pumpScreen(tester, MatchFormat.doubles);
    final side1 = tester.getTopLeft(find.text('Side 1').first);
    final side2 = tester.getTopLeft(find.text('Side 2').first);
    expect(side2.dy, side1.dy);
    expect(side2.dx, greaterThan(side1.dx));
  });

  testWidgets('locks landscape while open and releases it when closed', (tester) async {
    final orientations = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') orientations.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpScreen(tester, MatchFormat.doubles);
    expect(orientations, [
      ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
    ]);
    await tester.pumpWidget(const SizedBox());
    expect(orientations.last, isEmpty);
  });

  testWidgets('singles asks for one player per side and no team name', (tester) async {
    await pumpScreen(tester, MatchFormat.singles);
    expect(find.widgetWithText(TextField, 'Team name (optional)'), findsNothing);
    expect(find.widgetWithText(TextField, 'First name'), findsNWidgets(2));
  });

  testWidgets('Start Match stays off until every first and last name is filled', (tester) async {
    await pumpScreen(tester, MatchFormat.doubles);
    await enterPlayers(tester, [('Ana', 'Smith'), ('Raj', 'Patel'), ('Lee', 'Wong')]);
    await enter(tester, 'First name', 3, 'Mo');
    expect(startEnabled(tester), isFalse);
    await enter(tester, 'Last name', 3, 'Khan');
    expect(startEnabled(tester), isTrue);
  });

  testWidgets('starting passes the game and sides', (tester) async {
    await pumpScreen(tester, MatchFormat.doubles);
    await enter(tester, 'Team name (optional)', 0, 'Smashers');
    await enterPlayers(tester, [('Ana', 'Smith'), ('Raj', 'Patel'), ('Lee', 'Wong'), ('Mo', 'Khan')]);
    await startMatch(tester);

    expect(savedSides, same(started!.sides), reason: 'the sides sent to the database are the ones scored');
    expect(started!.game.gameTo, 11);
    expect(started!.id, 'K7P2QXAB', reason: 'the database picks the match ID');
    expect(started!.scorerToken, 'secret-token');
    expect(started!.sides[0].displayName, 'Smashers');
    expect(started!.sides[0].players.map((p) => p.displayName), ['Ana Smith', 'Raj Patel']);
    expect(started!.sides[1].displayName, 'Wong / Khan');
    expect(started!.sides[1].players.first.firstName, 'Lee');
    expect(started!.sides[1].players.first.lastName, 'Wong');
  });

  testWidgets('a singles side is named after its player', (tester) async {
    await pumpScreen(tester, MatchFormat.singles);
    await enterPlayers(tester, [('Ana', 'Smith'), ('Lee', 'Wong')]);
    await startMatch(tester);
    expect(started!.sides.map((s) => s.displayName), ['Ana Smith', 'Lee Wong']);
    expect(started!.sides[0].players, hasLength(1));
  });

  testWidgets('shows a spinner while the match is being created and blocks a second tap', (tester) async {
    final response = Completer<CreatedGame>();
    await pumpScreen(tester, MatchFormat.singles, createGame: (_, _) => response.future);
    await enterPlayers(tester, [('Ana', 'Smith'), ('Lee', 'Wong')]);
    await tester.tap(find.text('Start Match'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    response.complete((id: 'K7P2QXAB', scorerToken: 'secret-token'));
    await tester.pump();
    expect(started!.id, 'K7P2QXAB');
  });

  testWidgets('if the match cannot be created, says so and lets the scorer try again', (tester) async {
    await pumpScreen(tester, MatchFormat.singles, createGame: (_, _) async => throw Exception('offline'));
    await enterPlayers(tester, [('Ana', 'Smith'), ('Lee', 'Wong')]);
    await startMatch(tester);

    expect(started, isNull);
    expect(find.text("Couldn't create the match. Check the connection and try again."), findsOneWidget);
    expect(startEnabled(tester), isTrue);
  });
}
