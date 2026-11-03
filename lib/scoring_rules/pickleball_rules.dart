import '../scoring/match_setup.dart';

/// Something the scorer records. Replaying a match's actions in order rebuilds its state.
sealed class ScoringAction {
  const ScoringAction();

  /// The action as the database's `apply_action` receives it.
  Map<String, Object?> toJson();
}

/// Starts a game. The server and, in doubles, the receiver both start in their side's right-hand court.
class StartGame extends ScoringAction {
  const StartGame({required this.servingSide, required this.server, this.receiver = 1});

  final int servingSide;

  /// Player positions (1 or 2) within their sides.
  final int server;
  final int receiver;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'start_game', 'serving_side': servingSide, 'server': server, 'receiver': receiver};
}

/// [side] won the rally.
class RallyWon extends ScoringAction {
  const RallyWon(this.side);

  final int side;

  @override
  Map<String, Object?> toJson() => {'type': 'rally_won', 'side': side};
}

/// The teams switched ends: compulsory midway through the deciding game, optional between games.
class SwitchEnds extends ScoringAction {
  const SwitchEnds();

  @override
  Map<String, Object?> toJson() => {'type': 'switch_ends'};
}

/// The state of a pickleball match. Sides and players are numbered 1 and 2, matching the database.
/// Lists are indexed by side number minus one. Produced by [PickleballRules]; treat it as read-only.
class PickleballState {
  PickleballState._(this.isDoubles);

  final bool isDoubles;

  /// The game being played, from 1.
  int game = 1;
  List<int> gamesWon = [0, 0];

  /// The final score of each finished game.
  List<List<int>> finishedGames = [];

  /// The current game's score.
  List<int> score = [0, 0];

  /// Null until the current game's first server is chosen.
  int? servingSide;

  /// The serving player's position within [servingSide].
  int server = 1;

  /// 1 or 2 in doubles, null in singles.
  int? serverNumber;

  /// Which player of each side stands in the right-hand court (doubles only).
  List<int> rightCourt = [1, 1];

  /// Whether a side has reached the midpoint of the deciding game, when the teams must switch ends.
  bool midpointReached = false;

  /// Side 1 starts at the left end, as the scorer sees the court. Each [SwitchEnds] flips it.
  bool side1OnLeft = true;

  /// The side that won the match.
  int? winner;

  bool get isAwaitingServe => winner == null && servingSide == null;

  /// The score as the server calls it: server's score, receiver's score, and in doubles the server number.
  String get call {
    final serving = servingSide;
    if (serving == null) return isDoubles ? '0-0-2' : '0-0';
    final text = '${score[serving - 1]}-${score[2 - serving]}';
    return serverNumber == null ? text : '$text-$serverNumber';
  }

  bool isOnRight(int side, int player) {
    if (isDoubles) return rightCourt[side - 1] == player;
    // Singles players stand on the right when the server's score is even.
    final serving = servingSide;
    return serving == null || score[serving - 1].isEven;
  }

  PickleballState _clone() => PickleballState._(isDoubles)
    ..game = game
    ..gamesWon = [...gamesWon]
    ..finishedGames = [for (final game in finishedGames) [...game]]
    ..score = [...score]
    ..servingSide = servingSide
    ..server = server
    ..serverNumber = serverNumber
    ..rightCourt = [...rightCourt]
    ..midpointReached = midpointReached
    ..side1OnLeft = side1OnLeft
    ..winner = winner;
}

/// Side-out scoring, win by 2. Throws [StateError] for an action that isn't allowed in the current state.
class PickleballRules {
  const PickleballRules(this.setup);

  final GameSetup setup;

  static const winBy = 2;

  bool get isDoubles => setup.format == MatchFormat.doubles;

  int get _gamesToWin => setup.bestOf ~/ 2 + 1;

  PickleballState replay(Iterable<ScoringAction> actions) => actions.fold(PickleballState._(isDoubles), apply);

  PickleballState apply(PickleballState state, ScoringAction action) {
    if (state.winner != null) throw StateError('The match is over.');
    final next = state._clone();
    switch (action) {
      case StartGame():
        _startGame(next, action);
      case RallyWon():
        _rallyWon(next, action.side);
      case SwitchEnds():
        next.side1OnLeft = !next.side1OnLeft;
    }
    return next;
  }

  void _startGame(PickleballState s, StartGame action) {
    if (s.servingSide != null) throw StateError('Game ${s.game} has already started.');
    s
      ..servingSide = action.servingSide
      ..server = action.server
      // Doubles starts at 0-0-2: the first serving team gets only one server.
      ..serverNumber = isDoubles ? 2 : null
      ..rightCourt[action.servingSide - 1] = action.server
      ..rightCourt[2 - action.servingSide] = action.receiver;
  }

  void _rallyWon(PickleballState s, int side) {
    final serving = s.servingSide;
    if (serving == null) throw StateError('Choose who serves first.');
    if (side != 1 && side != 2) throw ArgumentError.value(side, 'side', 'must be 1 or 2');

    if (side == serving) {
      // Only the serving side scores. Its players swap courts so the server serves to the other receiver.
      s.score[side - 1]++;
      if (isDoubles) s.rightCourt[side - 1] = 3 - s.rightCourt[side - 1];
      _checkGameOver(s, side);
    } else if (s.serverNumber == 1) {
      // The partner serves next, from wherever they are standing.
      s
        ..server = 3 - s.server
        ..serverNumber = 2;
    } else {
      // Side-out: the receiving side's player in the right-hand court serves next.
      s
        ..servingSide = side
        ..server = s.rightCourt[side - 1]
        ..serverNumber = isDoubles ? 1 : null;
    }
  }

  void _checkGameOver(PickleballState s, int side) {
    final mine = s.score[side - 1];
    final theirs = s.score[2 - side];

    final isDecidingGame = s.gamesWon.every((won) => won == _gamesToWin - 1);
    if (isDecidingGame && mine >= (setup.gameTo + 1) ~/ 2) s.midpointReached = true;

    if (mine < setup.gameTo || mine - theirs < winBy) return;
    s.finishedGames.add([...s.score]);
    s.gamesWon[side - 1]++;
    if (s.gamesWon[side - 1] == _gamesToWin) {
      s.winner = side;
      return;
    }
    s
      ..game += 1
      ..score = [0, 0]
      ..servingSide = null
      ..serverNumber = null
      ..midpointReached = false;
  }
}
