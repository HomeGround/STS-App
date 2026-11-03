/// What the ticker needs about a match: names and the latest score, as `get_ticker_snapshot` returns them.
class TickerSnapshot {
  const TickerSnapshot({
    required this.id,
    required this.isDoubles,
    required this.version,
    required this.sideNames,
    required this.players,
    required this.game,
    required this.gamesWon,
    required this.score,
    required this.servingSide,
    required this.call,
    required this.winner,
  });

  factory TickerSnapshot.fromJson(Map<String, dynamic> json) {
    final isDoubles = json['match_format'] == 'doubles';
    final sides = [...(json['sides'] as List).cast<Map<String, dynamic>>()]
      ..sort((a, b) => (a['side_number'] as int).compareTo(b['side_number'] as int));
    // A match that hasn't started has an empty state.
    final state = json['state'] as Map<String, dynamic>? ?? const {};
    List<int> pair(String key) => [for (final n in (state[key] as List?) ?? const [0, 0]) (n as num).toInt()];

    return TickerSnapshot(
      id: json['id'] as String,
      isDoubles: isDoubles,
      version: (json['version'] as num).toInt(),
      sideNames: [for (final side in sides) side['display_name'] as String],
      players: [for (final side in sides) (side['players'] as List).cast<String>()],
      game: (state['game'] as num?)?.toInt() ?? 1,
      gamesWon: pair('games_won'),
      score: pair('score'),
      servingSide: (state['serving_side'] as num?)?.toInt(),
      call: state['call'] as String? ?? (isDoubles ? '0-0-2' : '0-0'),
      winner: (state['winner'] as num?)?.toInt(),
    );
  }

  /// The match ID, such as `K7P2QXAB`.
  final String id;
  final bool isDoubles;

  /// Goes up with every recorded action, so a changed version means the ticker needs redrawing.
  final int version;

  /// Side 1 then side 2.
  final List<String> sideNames;
  final List<List<String>> players;

  /// The game being played, from 1.
  final int game;
  final List<int> gamesWon;

  /// The current game's score, side 1 then side 2.
  final List<int> score;

  /// Null before a game's first serve.
  final int? servingSide;

  /// The score as the server calls it, such as `4-2-1`.
  final String call;
  final int? winner;

  String get title => '${sideNames[0]} vs ${sideNames[1]}';
}
