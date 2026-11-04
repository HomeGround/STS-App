import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:sts/mqtt/broker.dart';
import 'package:sts/mqtt/match_broadcast.dart';
import 'package:sts/mqtt/match_feed.dart';
import 'package:sts/onboarding/sport.dart';
import 'package:sts/scoring/match_setup.dart';

/// Needs a running broker, so it's skipped unless one is named:
/// `flutter test test/mqtt --dart-define=MQTT_TEST_HOST=localhost`
const _host = String.fromEnvironment('MQTT_TEST_HOST');

void main() {
  test('a streamer finds a published match and follows its updates', () async {
    const settings = BrokerSettings(host: _host, port: 1883);
    // A fresh ID each run, so retained messages from earlier runs don't interfere.
    final id = 'T${Random().nextInt(1 << 28).toRadixString(36).toUpperCase().padLeft(7, '0')}';
    final match = MatchSetup(
      id: id,
      scorerToken: 'unused',
      game: const GameSetup(sport: Sport.pickleball, format: MatchFormat.singles, bestOf: 3, gameTo: 11),
      sides: const [
        SideSetup(displayName: 'Hawks', players: [PlayerSetup(firstName: 'Ana', lastName: 'Smith')]),
        SideSetup(displayName: 'Snakes', players: [PlayerSetup(firstName: 'Lee', lastName: 'Wong')]),
      ],
    );
    const feed = MatchFeed(settings);
    final broadcast = MatchBroadcast(settings);
    addTearDown(broadcast.close);

    expect(await feed.lookup(id), isNull, reason: 'nothing is published for this ID yet');

    broadcast.publish(id, matchMessage(match, version: 0, state: const {}));
    final found = await feed.lookup(id);
    expect(found?.title, 'Hawks vs Snakes', reason: 'the retained message reaches a streamer that joins later');
    expect(found?.version, 0);

    final updates = feed.watch(id).map((m) => (m.version, m.call)).take(2).toList();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    broadcast.publish(id, matchMessage(match, version: 1, state: {'game': 1, 'score': [1, 0], 'serving_side': 1, 'call': '1-0'}));
    expect(await updates.timeout(const Duration(seconds: 5)), [(0, '0-0'), (1, '1-0')]);

    // Clear the retained message so the broker doesn't keep test matches.
    final cleaner = await connectToBroker(settings, role: 'test');
    cleaner.publishMessage(matchTopic(id), MqttQos.atMostOnce, MqttClientPayloadBuilder().payload!, retain: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    cleaner.disconnect();
  }, skip: _host.isEmpty ? 'Set --dart-define=MQTT_TEST_HOST to run against a broker' : false);
}
