import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sts/streaming/ticker_painter.dart';
import 'package:sts/streaming/ticker_snapshot.dart';

/// What `get_ticker_snapshot` returns for a doubles match two points into game 2.
Map<String, dynamic> snapshotJson({Map<String, dynamic>? state}) => {
  'id': 'K7P2QXAB',
  'status': 'in_progress',
  'match_format': 'doubles',
  'version': 27,
  'state': state ??
      {
        'game': 2,
        'games_won': [1, 0],
        'score': [2, 0],
        'serving_side': 1,
        'server': 1,
        'server_number': 1,
        'call': '2-0-1',
        'winner': null,
      },
  'sides': [
    {'side_number': 2, 'display_name': 'Wong / Khan', 'players': ['Lee Wong', 'Mo Khan']},
    {'side_number': 1, 'display_name': 'Smashers', 'players': ['Ana Smith', 'Raj Patel']},
  ],
};

void main() {
  test('reads the snapshot, with sides in side-number order', () {
    final match = TickerSnapshot.fromJson(snapshotJson());
    expect(match.title, 'Smashers vs Wong / Khan');
    expect(match.players[1], ['Lee Wong', 'Mo Khan']);
    expect(match.version, 27);
    expect(match.game, 2);
    expect(match.gamesWon, [1, 0]);
    expect(match.score, [2, 0]);
    expect(match.servingSide, 1);
    expect(match.call, '2-0-1');
  });

  test('a match that has not started reads as 0-0 in game 1', () {
    final match = TickerSnapshot.fromJson(snapshotJson(state: {}));
    expect(match.game, 1);
    expect(match.score, [0, 0]);
    expect(match.servingSide, isNull);
    expect(match.call, '0-0-2');
  });

  test('draws the ticker as a PNG exactly the size of the stream', () async {
    final match = TickerSnapshot.fromJson(snapshotJson());
    for (final (width, height) in [(1920, 1080), (1280, 720)]) {
      final png = await renderTicker(match, width: width, height: height);
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      // The PNG header holds the width and height as big-endian numbers.
      final header = ByteData.sublistView(png, 16, 24);
      expect((header.getUint32(0), header.getUint32(4)), (width, height));
    }
  });
}
