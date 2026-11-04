import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../streaming/ticker_snapshot.dart';
import 'broker.dart';

/// Follows a match over MQTT for the streaming device. Never talks to the database.
class MatchFeed {
  const MatchFeed(this.settings);

  final BrokerSettings settings;

  /// How long to wait for a match's retained message before deciding no such match is being scored.
  static const lookupTimeout = Duration(seconds: 4);

  /// The match as the scorer last published it, or null if nothing is published for this ID.
  /// Throws [BrokerException] if the broker can't be reached.
  Future<TickerSnapshot?> lookup(String matchId) async {
    try {
      return await watch(matchId).first.timeout(lookupTimeout);
    } on TimeoutException {
      return null;
    }
  }

  /// Every update to the match, starting with the latest. Connects on listen and disconnects on cancel.
  Stream<TickerSnapshot> watch(String matchId) {
    final topic = matchTopic(matchId);
    late final StreamController<TickerSnapshot> controller;
    MqttClient? client;
    var cancelled = false;

    controller = StreamController(
      onListen: () async {
        try {
          final connected = await connectToBroker(settings, role: 'streamer');
          if (cancelled) return connected.disconnect();
          client = connected;
          connected.updates!.listen((messages) {
            for (final message in messages) {
              if (message.topic != topic) continue;
              final publish = message.payload as MqttPublishMessage;
              try {
                final json = jsonDecode(utf8.decode(publish.payload.message)) as Map<String, dynamic>;
                controller.add(TickerSnapshot.fromJson(json));
              } catch (error) {
                debugPrint('Ignoring an unreadable message on $topic: $error');
              }
            }
          });
          connected.subscribe(topic, MqttQos.atLeastOnce);
        } catch (error) {
          controller.addError(error);
        }
      },
      onCancel: () {
        cancelled = true;
        client?.disconnect();
      },
    );
    return controller.stream;
  }
}
