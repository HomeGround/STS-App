import 'package:flutter_test/flutter_test.dart';
import 'package:sts/mqtt/broker.dart';
import 'package:sts/mqtt/match_broadcast.dart';

void main() {
  test('reports offline with the reason when the broker cannot be reached, and keeps trying', () async {
    // Nothing listens on port 1, so the connection is refused straight away.
    final broadcast = MatchBroadcast(const BrokerSettings(host: '127.0.0.1', port: 1));
    addTearDown(broadcast.close);
    final seen = <LinkState>[];
    broadcast.status.addListener(() => seen.add(broadcast.status.value.state));

    broadcast.publish('K7P2QXAB', {'version': 0});
    while (broadcast.status.value.state != LinkState.offline) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(broadcast.status.value.problem, "Couldn't reach the score server at 127.0.0.1:1.");

    // It tries again after the retry delay.
    await Future<void>.delayed(MatchBroadcast.retryDelay + const Duration(seconds: 1));
    expect(seen.where((s) => s == LinkState.connecting), isNotEmpty);
    expect(seen.last, LinkState.offline);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('says when MQTT is not set up at all', () async {
    final broadcast = MatchBroadcast(const BrokerSettings(host: '', port: 1883));
    addTearDown(broadcast.close);
    broadcast.publish('K7P2QXAB', {'version': 0});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(broadcast.status.value.state, LinkState.offline);
    expect(broadcast.status.value.problem, contains('MQTT is not set up'));
  });
}
