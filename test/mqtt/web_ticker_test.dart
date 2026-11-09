import 'package:flutter_test/flutter_test.dart';
import 'package:sts/mqtt/web_ticker.dart';

/// A `matchMessage` for a doubles match, 5-3 in game 2 of 3.
Map<String, Object?> match({String status = 'in_progress', Map<String, Object?>? state}) => {
  'id': 'K7P2QXAB',
  'status': status,
  'match_format': 'doubles',
  'best_of': 3,
  'version': 21,
  'state': state ?? {'game': 2, 'games_won': [1, 0], 'score': [5, 3], 'serving_side': 1, 'call': '5-3-1'},
  'sides': [
    {'side_number': 2, 'display_name': 'Snakes', 'players': ['Lee Wong', 'Mo Khan']},
    {'side_number': 1, 'display_name': 'Hawks', 'players': ['Ana Smith', 'Raj Patel']},
  ],
};

void main() {
  test('publishes on the topic the web ticker subscribes to', () {
    expect(webTickerTopic('K7P2QXAB'), 'sports/pickleball/match/K7P2QXAB');
  });

  test('builds the payload the web ticker expects, side 1 as team A', () {
    expect(webTickerMessage(match()), {
      'tournamentName': 'Hawks vs Snakes',
      'courtName': '',
      'status': 'live',
      'currentSet': 2,
      'totalSets': 3,
      'teamA': {
        'teamName': 'Hawks',
        'score': 5,
        'players': [{'name': 'Ana Smith'}, {'name': 'Raj Patel'}],
      },
      'teamB': {
        'teamName': 'Snakes',
        'score': 3,
        'players': [{'name': 'Lee Wong'}, {'name': 'Mo Khan'}],
      },
    });
  });

  test('before the first serve it shows game 1 at 0-0', () {
    final ticker = webTickerMessage(match(status: 'setup', state: {}));
    expect(ticker['status'], 'live');
    expect(ticker['currentSet'], 1);
    expect((ticker['teamA'] as Map)['score'], 0);
    expect((ticker['teamB'] as Map)['score'], 0);
  });

  test('a won match is marked completed', () {
    expect(webTickerMessage(match(status: 'completed'))['status'], 'completed');
  });
}
