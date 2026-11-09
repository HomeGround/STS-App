/// The web ticker at ticker.homegroundapp.com/match/ID subscribes to this topic.
String webTickerTopic(String matchId) => 'sports/pickleball/match/$matchId';

/// Turns a `matchMessage` into the payload the web ticker reads, for example:
/// `{"tournamentName":"…","courtName":"…","status":"live","currentSet":1,"totalSets":3,
///   "teamA":{"teamName":"Akash","score":5,"players":[{"name":"A1"}]},"teamB":{…}}`.
/// A "set" here is a pickleball game, and `score` is the points in the current game.
Map<String, Object?> webTickerMessage(Map<String, Object?> match) {
  final state = (match['state'] as Map?) ?? const {};
  final sides = [...(match['sides'] as List).cast<Map<String, Object?>>()]
    ..sort((a, b) => (a['side_number'] as int).compareTo(b['side_number'] as int));
  final score = (state['score'] as List?) ?? const [0, 0];

  Map<String, Object?> team(int index) => {
    'teamName': sides[index]['display_name'],
    'score': (score[index] as num).toInt(),
    'players': [
      for (final name in (sides[index]['players'] as List).cast<String>()) {'name': name},
    ],
  };

  return {
    'tournamentName': '${sides[0]['display_name']} vs ${sides[1]['display_name']}',
    'courtName': '',
    'status': match['status'] == 'completed' ? 'completed' : 'live',
    'currentSet': (state['game'] as num?)?.toInt() ?? 1,
    'totalSets': match['best_of'],
    'teamA': team(0),
    'teamB': team(1),
  };
}
