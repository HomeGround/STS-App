import 'package:flutter_test/flutter_test.dart';
import 'package:sts/onboarding/sport.dart';
import 'package:sts/scoring/match_setup.dart';
import 'package:sts/scoring_rules/pickleball_rules.dart';

PickleballRules rules(MatchFormat format, {int bestOf = 3, int gameTo = 11}) =>
    PickleballRules(GameSetup(sport: Sport.pickleball, format: format, bestOf: bestOf, gameTo: gameTo));

/// Applies actions one at a time and keeps the latest state.
class Match {
  Match(this.rules) : state = rules.replay([]);

  final PickleballRules rules;
  PickleballState state;

  void start(int side, int server, [int receiver = 1]) =>
      state = rules.apply(state, StartGame(servingSide: side, server: server, receiver: receiver));

  void rally(int side) => state = rules.apply(state, RallyWon(side));

  /// Gives [side] the serve if needed, then lets it win [points] points.
  void score(int side, int points) {
    for (var i = 0; i < points; i++) {
      while (state.servingSide != side) {
        rally(side);
      }
      rally(side);
    }
  }
}

void main() {
  group('doubles', () {
    test('follows the serve through points, second server and side-outs', () {
      final m = Match(rules(MatchFormat.doubles));
      // Side 1, player 1 serves first. Side 2, player 2 receives.
      m.start(1, 1, 2);
      expect(m.state.call, '0-0-2');
      expect([m.state.isOnRight(1, 1), m.state.isOnRight(2, 2)], [true, true]);

      // Side 1 wins: point, and the server swaps to the left-hand court.
      m.rally(1);
      expect(m.state.call, '1-0-2');
      expect(m.state.server, 1);
      expect(m.state.isOnRight(1, 1), isFalse);

      // Side 2 wins: the first serving team only had one server, so it's a side-out.
      // Side 2's player in the right-hand court (player 2) serves as server 1.
      m.rally(2);
      expect(m.state.call, '0-1-1');
      expect([m.state.servingSide, m.state.server], [2, 2]);

      // Side 2 wins: point, server swaps courts. The receiving side doesn't move.
      m.rally(2);
      expect(m.state.call, '1-1-1');
      expect(m.state.isOnRight(2, 1), isTrue);
      expect(m.state.isOnRight(1, 2), isTrue);

      // Side 1 wins: server 1 loses the serve, so the partner serves as server 2.
      m.rally(1);
      expect(m.state.call, '1-1-2');
      expect([m.state.servingSide, m.state.server], [2, 1]);

      // Side 1 wins again: side-out. Side 1's player in the right-hand court (player 2) serves.
      m.rally(1);
      expect(m.state.call, '1-1-1');
      expect([m.state.servingSide, m.state.server], [1, 2]);
    });
  });

  group('singles', () {
    test('has no server number and sides out on the first lost rally', () {
      final m = Match(rules(MatchFormat.singles));
      m.start(2, 1);
      expect(m.state.call, '0-0');

      m.rally(2);
      expect(m.state.call, '1-0');
      m.rally(1);
      expect(m.state.call, '0-1');
      expect(m.state.servingSide, 1);
    });

    test('players stand on the right when the server\'s score is even', () {
      final m = Match(rules(MatchFormat.singles));
      m.start(1, 1);
      expect(m.state.isOnRight(1, 1), isTrue);
      m.rally(1);
      expect([m.state.isOnRight(1, 1), m.state.isOnRight(2, 1)], [false, false]);
      m.rally(2);
      // Side 2 serves at 0, an even score.
      expect(m.state.isOnRight(2, 1), isTrue);
    });
  });

  group('games and match', () {
    test('a game needs the target score and a 2-point lead', () {
      final m = Match(rules(MatchFormat.singles));
      m.start(1, 1);
      m.score(1, 10);
      m.score(2, 10);
      m.score(1, 1);
      expect(m.state.game, 1, reason: '11-10 is not a 2-point lead');
      m.score(1, 1);
      expect(m.state.game, 2);
      expect(m.state.finishedGames, [
        [12, 10],
      ]);
      expect(m.state.gamesWon, [1, 0]);
    });

    test('each game starts with the first server unchosen and the score at zero', () {
      final m = Match(rules(MatchFormat.doubles));
      m.start(1, 1, 1);
      m.score(1, 11);
      expect(m.state.isAwaitingServe, isTrue);
      expect(m.state.score, [0, 0]);
      expect(m.state.call, '0-0-2');
      expect(() => m.rally(1), throwsStateError);
    });

    test('best of 3 is won by the first side to win 2 games, and the match then accepts nothing', () {
      final m = Match(rules(MatchFormat.singles, gameTo: 15));
      m.start(1, 1);
      m.score(1, 15);
      m.start(2, 1);
      m.score(2, 15);
      m.start(1, 1);
      m.score(1, 15);
      expect(m.state.winner, 1);
      expect(m.state.gamesWon, [2, 1]);
      expect(() => m.rally(1), throwsStateError);
    });

    test('best of 1 is won in one game', () {
      final m = Match(rules(MatchFormat.singles, bestOf: 1));
      m.start(1, 1);
      m.score(2, 11);
      expect(m.state.winner, 2);
    });

    test('teams must switch ends midway through the deciding game only', () {
      final m = Match(rules(MatchFormat.singles));
      m.start(1, 1);
      m.score(1, 6);
      expect(m.state.midpointReached, isFalse, reason: 'game 1 is not the deciding game');
      m.score(1, 5);
      m.start(1, 1);
      m.score(2, 6);
      expect(m.state.midpointReached, isFalse, reason: 'game 2 is not the deciding game');
      m.score(2, 5);
      m.start(1, 1);
      m.score(2, 5);
      expect(m.state.midpointReached, isFalse);
      m.score(2, 1);
      expect(m.state.midpointReached, isTrue, reason: 'a side reached 6 in the deciding game');
    });

    test('the deciding-game switch happens at 8 for games to 15 and 11 for games to 21', () {
      for (final (gameTo, switchAt) in [(15, 8), (21, 11)]) {
        final m = Match(rules(MatchFormat.singles, bestOf: 1, gameTo: gameTo));
        m.start(1, 1);
        m.score(1, switchAt - 1);
        expect(m.state.midpointReached, isFalse);
        m.score(1, 1);
        expect(m.state.midpointReached, isTrue);
      }
    });
  });

  test('switching ends flips which side is on the left, without touching the score or serve', () {
    final m = Match(rules(MatchFormat.doubles));
    expect(m.state.side1OnLeft, isTrue);
    m.start(1, 1, 2);
    m.rally(1);
    final call = m.state.call;

    m.state = m.rules.apply(m.state, const SwitchEnds());
    expect(m.state.side1OnLeft, isFalse);
    expect(m.state.call, call);
    m.state = m.rules.apply(m.state, const SwitchEnds());
    expect(m.state.side1OnLeft, isTrue);
  });

  test('ends stay switched into the next game', () {
    final m = Match(rules(MatchFormat.singles));
    m.start(1, 1);
    m.score(1, 11);
    m.state = m.rules.apply(m.state, const SwitchEnds());
    m.start(2, 1);
    expect(m.state.side1OnLeft, isFalse);
  });

  test('actions are sent to the database in this shape', () {
    expect(const StartGame(servingSide: 2, server: 1, receiver: 2).toJson(),
        {'type': 'start_game', 'serving_side': 2, 'server': 1, 'receiver': 2});
    expect(const RallyWon(1).toJson(), {'type': 'rally_won', 'side': 1});
    expect(const SwitchEnds().toJson(), {'type': 'switch_ends'});
  });

  test('replaying actions rebuilds the same state, so undo is replaying all but the last', () {
    final r = rules(MatchFormat.doubles);
    final actions = [const StartGame(servingSide: 1, server: 2, receiver: 1), const RallyWon(1), const RallyWon(2)];
    expect(r.replay(actions).call, '0-1-1');
    expect(r.replay(actions.take(2)).call, '1-0-2');
  });

  test('rejects rallies before the serve is chosen and a second start', () {
    final m = Match(rules(MatchFormat.doubles));
    expect(() => m.rally(1), throwsStateError);
    m.start(1, 1);
    expect(() => m.start(2, 1), throwsStateError);
    expect(() => m.rally(3), throwsArgumentError);
  });
}
