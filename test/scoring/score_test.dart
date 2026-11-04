import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/mqtt/match_broadcast.dart';
import 'package:sts/onboarding/sport.dart';
import 'package:sts/scoring/match_setup.dart';
import 'package:sts/scoring/score.dart';
import 'package:sts/scoring/score_sync.dart';

const _doubles = MatchSetup(
  id: 'K7P2QXAB',
  scorerToken: 'secret-token',
  game: GameSetup(sport: Sport.pickleball, format: MatchFormat.doubles, bestOf: 3, gameTo: 11),
  sides: [
    SideSetup(
      displayName: 'Smashers',
      players: [
        PlayerSetup(firstName: 'Ana', lastName: 'Smith'),
        PlayerSetup(firstName: 'Raj', lastName: 'Patel'),
      ],
    ),
    SideSetup(
      displayName: 'Wong / Khan',
      players: [
        PlayerSetup(firstName: 'Lee', lastName: 'Wong'),
        PlayerSetup(firstName: 'Mo', lastName: 'Khan'),
      ],
    ),
  ],
);

void main() {
  /// What the screen sent to the stand-in database, in order.
  late List<ActionRequest> sent;

  /// What the screen published for the streaming devices, in order.
  late List<Map<String, Object?>> published;

  /// [applyAction] stands in for the database. By default it accepts every action and
  /// answers with a state naming the version, so tests can see which state was published.
  Future<void> pumpScreen(WidgetTester tester, {ApplyAction? applyAction, ValueListenable<LinkStatus>? streamLink}) async {
    sent = [];
    published = [];
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ScoreScreen(
        match: _doubles,
        applyAction: applyAction ??
            (request) async {
              sent.add(request);
              final version = request.expectedVersion + 1;
              return (version: version, state: <String, dynamic>{'call': 'v$version'});
            },
        streamLink: streamLink,
        broadcast: (matchId, message) {
          expect(matchId, 'K7P2QXAB');
          published.add(message);
        },
      ),
    ));
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }

  Finder startButton() => find.byKey(const ValueKey('start-game'));

  /// Picks the first server and receiver, then presses Start.
  Future<void> startGame(WidgetTester tester, {required String server, required String receiver}) async {
    await tap(tester, server);
    await tap(tester, receiver);
    await tester.tap(startButton());
    await tester.pump();
  }

  bool swapEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.swap_horiz)).onPressed != null;

  bool side1OnLeft(WidgetTester tester) =>
      tester.getTopLeft(find.text('Smashers')).dx < tester.getTopLeft(find.text('Wong / Khan')).dx;

  /// Starts a game, then lets [side] win [points] rallies in a row on its own serve.
  Future<void> playGame(
    WidgetTester tester, {
    required String server,
    required String receiver,
    required String side,
    required int points,
  }) async {
    await startGame(tester, server: server, receiver: receiver);
    for (var i = 0; i < points; i++) {
      await tap(tester, side);
    }
  }

  testWidgets('asks who serves and receives first, then waits for Start', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Who serves first? Tap the player.'), findsOneWidget);
    expect(startButton(), findsNothing);

    await tap(tester, 'Ana Smith');
    expect(find.text('Ana Smith · serves'), findsOneWidget);
    expect(find.text('Who receives first? Tap the player.'), findsOneWidget);
    // The receiver must come from the other side.
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Raj Patel')).onPressed, isNull);

    await tap(tester, 'Mo Khan');
    expect(find.text('Mo Khan · receives'), findsOneWidget);
    expect(find.text('Ana Smith serves to Mo Khan'), findsOneWidget);
    expect(find.text('Start match'), findsOneWidget);
    expect(sent, isEmpty, reason: 'nothing is recorded until Start is pressed');

    await tester.tap(startButton());
    await tester.pump();
    expect(find.text('Tap the side that won the rally'), findsOneWidget);
    expect(find.text('0-0-2'), findsOneWidget);
    expect(find.text('Server 2  '), findsOneWidget);

    await tap(tester, 'Smashers');
    expect(find.text('1-0-2'), findsOneWidget);
    await tap(tester, 'Wong / Khan');
    expect(find.text('0-1-1'), findsOneWidget);
  });

  testWidgets('swap works until the match starts, and again after undoing the start', (tester) async {
    await pumpScreen(tester);
    expect(swapEnabled(tester), isTrue);
    await tapTooltip(tester, 'Swap sides on screen');
    expect(side1OnLeft(tester), isFalse);

    await startGame(tester, server: 'Ana Smith', receiver: 'Mo Khan');
    expect(swapEnabled(tester), isFalse);
    expect(side1OnLeft(tester), isFalse, reason: 'the swap made before starting stays');

    // Undoing the start brings back the picks and the Start button, and allows swapping again.
    await tapTooltip(tester, 'Undo');
    expect(swapEnabled(tester), isTrue);
    expect(find.text('Ana Smith serves to Mo Khan'), findsOneWidget);
    expect(startButton(), findsOneWidget);
    expect(sent.last.action, {'type': 'undo'});
  });

  testWidgets('undo steps back through rallies, the start, and then the picks', (tester) async {
    await pumpScreen(tester);
    await startGame(tester, server: 'Ana Smith', receiver: 'Mo Khan');
    await tap(tester, 'Smashers');
    expect(find.text('1-0-2'), findsOneWidget);

    await tapTooltip(tester, 'Undo');
    expect(find.text('0-0-2'), findsOneWidget);
    expect(find.text('Tap the side that won the rally'), findsOneWidget);

    await tapTooltip(tester, 'Undo');
    expect(find.text('Ana Smith serves to Mo Khan'), findsOneWidget);

    await tapTooltip(tester, 'Undo');
    expect(find.text('Who receives first? Tap the player.'), findsOneWidget);

    await tapTooltip(tester, 'Undo');
    expect(find.text('Who serves first? Tap the player.'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed, isNull);
  });

  testWidgets('publishes the match when the screen opens, then each state the database confirms', (tester) async {
    await pumpScreen(tester);
    expect(published, hasLength(1), reason: 'streamers can find the match before the first point');
    expect(published.single, {
      'id': 'K7P2QXAB',
      'status': 'setup',
      'match_format': 'doubles',
      'version': 0,
      'state': <String, dynamic>{},
      'sides': [
        {'side_number': 1, 'display_name': 'Smashers', 'players': ['Ana Smith', 'Raj Patel']},
        {'side_number': 2, 'display_name': 'Wong / Khan', 'players': ['Lee Wong', 'Mo Khan']},
      ],
    });

    await startGame(tester, server: 'Ana Smith', receiver: 'Mo Khan');
    await tap(tester, 'Smashers');
    expect(published.map((m) => m['version']), [0, 1, 2]);
    expect(published.map((m) => (m['state'] as Map)['call']), [null, 'v1', 'v2'],
        reason: "what's published is the database's state, not the phone's own");
  });

  testWidgets('a small symbol shows whether the score reaches the streamers', (tester) async {
    final link = ValueNotifier<LinkStatus>((state: LinkState.connecting, problem: null));
    addTearDown(link.dispose);
    await pumpScreen(tester, streamLink: link);
    expect(find.byTooltip('Connecting the live score link…'), findsOneWidget);

    link.value = (state: LinkState.connected, problem: null);
    await tester.pump();
    expect(find.byIcon(Icons.sensors), findsOneWidget);
    expect(find.byTooltip('Live score link connected'), findsOneWidget);

    link.value = (state: LinkState.offline, problem: 'The score server rejected the MQTT username or password.');
    await tester.pump();
    expect(find.byIcon(Icons.sensors_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.sensors_off));
    await tester.pump();
    expect(find.text('Not reaching streamers. The score server rejected the MQTT username or password.'),
        findsWidgets, reason: 'tapping explains what is wrong');
  });

  testWidgets('never publishes a point the database did not save', (tester) async {
    await pumpScreen(tester, applyAction: (request) => Future.error(Exception('offline')));
    await startGame(tester, server: 'Ana Smith', receiver: 'Mo Khan');
    await tap(tester, 'Smashers');
    expect(published.map((m) => m['version']), [0]);
  });

  testWidgets('sends each game start, rally and undo to the database in order', (tester) async {
    await pumpScreen(tester);
    await startGame(tester, server: 'Ana Smith', receiver: 'Mo Khan');
    await tap(tester, 'Smashers');
    await tapTooltip(tester, 'Undo');

    expect(sent.map((r) => r.action), [
      {'type': 'start_game', 'serving_side': 1, 'server': 1, 'receiver': 2},
      {'type': 'rally_won', 'side': 1},
      {'type': 'undo'},
    ]);
    expect(sent.map((r) => r.expectedVersion), [0, 1, 2]);
    expect(sent.every((r) => r.gameId == 'K7P2QXAB' && r.scorerToken == 'secret-token'), isTrue);
    expect(sent.map((r) => r.clientEventId).toSet(), hasLength(3), reason: 'every action has its own ID');
    expect(find.byTooltip('All points saved'), findsOneWidget);
  });

  testWidgets('shows points waiting for the database, and a retry when saving fails', (tester) async {
    var online = false;
    final pending = Completer<SavedAction>();
    await pumpScreen(
      tester,
      applyAction: (request) {
        sent.add(request);
        if (!online) return Future.error(Exception('offline'));
        return pending.future;
      },
    );
    await startGame(tester, server: 'Ana Smith', receiver: 'Mo Khan');
    expect(find.text('Not saved · Retry'), findsOneWidget);
    // The score still moves on: points are kept and sent once saving works again.
    await tap(tester, 'Smashers');
    expect(find.text('1-0-2'), findsOneWidget);

    online = true;
    await tap(tester, 'Not saved · Retry');
    expect(find.text('2 saving'), findsOneWidget);
    expect(sent.last.clientEventId, sent.first.clientEventId, reason: 'a retry keeps the same ID');

    pending.complete((version: 1, state: <String, dynamic>{}));
    await tester.pump();
    expect(find.byTooltip('All points saved'), findsOneWidget);
  });

  testWidgets('shows the match ID and copies it when tapped', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpScreen(tester);
    await tap(tester, 'Match ID  K7P2QXAB');
    expect(copied, 'K7P2QXAB');
    expect(find.text('Match ID copied'), findsOneWidget);
  });

  testWidgets('after a game, asks whether to switch ends and records it if so', (tester) async {
    await pumpScreen(tester);
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 11);
    expect(find.text('Game 1 is over'), findsOneWidget);
    expect(find.text('Do the teams want to switch ends?'), findsOneWidget);

    await tap(tester, 'Switch ends');
    expect(find.text('Game 1 is over'), findsNothing);
    expect(side1OnLeft(tester), isFalse);
    expect(find.text('Game 2'), findsOneWidget);
    expect(sent.last.action, {'type': 'switch_ends'});

    // Undo takes the switch back, like any other action.
    await tapTooltip(tester, 'Undo');
    expect(side1OnLeft(tester), isTrue);
    expect(sent.last.action, {'type': 'undo'});
  });

  testWidgets('after a game, answering No keeps the sides and records nothing', (tester) async {
    await pumpScreen(tester);
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 11);
    await tap(tester, 'No');
    expect(side1OnLeft(tester), isTrue);
    expect(sent.last.action, {'type': 'rally_won', 'side': 1});
  });

  testWidgets('the next game has its own Start button', (tester) async {
    await pumpScreen(tester);
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 11);
    await tap(tester, 'No');
    await tap(tester, 'Lee Wong');
    await tap(tester, 'Ana Smith');
    expect(find.text('Start game 2'), findsOneWidget);
  });

  testWidgets('score cards show games won', (tester) async {
    await pumpScreen(tester);
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 11);
    await tap(tester, 'No');
    expect(find.text('Games won 1'), findsOneWidget);
    expect(find.text('Games won 0'), findsOneWidget);
  });

  testWidgets('celebrates the winner when the match is won', (tester) async {
    await pumpScreen(tester);
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 11);
    await tap(tester, 'No');
    await playGame(tester, server: 'Raj Patel', receiver: 'Lee Wong', side: 'Smashers', points: 11);
    await tester.pumpAndSettle();

    expect(find.text('MATCH WON'), findsOneWidget);
    expect(find.text('Ana Smith & Raj Patel'), findsOneWidget);
    expect(find.text('2–0'), findsOneWidget, reason: 'games, winner first');
    expect(find.text('22–0'), findsOneWidget, reason: 'points, winner first');
    expect(find.text('G1  11–0     G2  11–0'), findsOneWidget);

    await tap(tester, 'Done');
    await tester.pumpAndSettle();
    expect(find.text('MATCH WON'), findsNothing);
    expect(find.text('Smashers win the match'), findsOneWidget);
  });

  testWidgets('the deciding game\'s midpoint switch is compulsory', (tester) async {
    await pumpScreen(tester);
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 11);
    await tap(tester, 'No');
    await playGame(tester, server: 'Lee Wong', receiver: 'Ana Smith', side: 'Wong / Khan', points: 11);
    await tap(tester, 'No');
    await playGame(tester, server: 'Ana Smith', receiver: 'Mo Khan', side: 'Smashers', points: 5);
    expect(find.text('Switch ends'), findsNothing);

    await tap(tester, 'Smashers');
    expect(find.text('Midpoint of the deciding game. Teams, please switch ends.'), findsOneWidget);
    expect(find.text('No'), findsNothing);
    await tap(tester, 'OK');
    expect(side1OnLeft(tester), isFalse);
    expect(sent.last.action, {'type': 'switch_ends'});
  });
}
