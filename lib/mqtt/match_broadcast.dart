import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../scoring/match_setup.dart';
import 'broker.dart';

/// The message on a match's topic: the names and the latest confirmed state, as `TickerSnapshot.fromJson` reads it.
/// [state] is the state `apply_action` returned; an empty map before the first action.
Map<String, Object?> matchMessage(MatchSetup match, {required int version, required Map<String, dynamic> state}) => {
  'id': match.id,
  'status': state['winner'] != null
      ? 'completed'
      : state['serving_side'] != null || ((state['game'] as num?) ?? 1) > 1
      ? 'in_progress'
      : 'setup',
  'match_format': match.game.format.name,
  'version': version,
  'state': state,
  'sides': [
    for (final (i, side) in match.sides.indexed)
      {
        'side_number': i + 1,
        'display_name': side.displayName,
        'players': [for (final player in side.players) player.displayName],
      },
  ],
};

/// Whether the scorer's updates are reaching the broker.
enum LinkState { connecting, connected, offline }

typedef LinkStatus = ({LinkState state, String? problem});

/// Publishes the scorer's match to MQTT for the streaming devices.
///
/// Each message is retained, so a streaming device that joins mid-match gets the latest one straight away.
/// Only the newest message matters: if the broker is unreachable, the latest is sent once it's back.
class MatchBroadcast {
  MatchBroadcast(this.settings);

  final BrokerSettings settings;

  /// How long to wait before trying again after failing to connect.
  static const retryDelay = Duration(seconds: 5);

  /// Starts as connecting: nothing has been tried until the first publish.
  final status = ValueNotifier<LinkStatus>((state: LinkState.connecting, problem: null));

  MqttServerClient? _client;
  Future<void>? _connecting;
  Timer? _retry;
  ({String topic, String payload})? _latest;
  var _isClosed = false;

  void publish(String matchId, Map<String, Object?> message) {
    _latest = (topic: matchTopic(matchId), payload: jsonEncode(message));
    _sendLatest();
  }

  void _setStatus(LinkState state, [String? problem]) {
    if (!_isClosed) status.value = (state: state, problem: problem);
  }

  Future<void> _sendLatest() async {
    final client = _client;
    if (client == null) return _connect();
    final latest = _latest;
    if (latest == null || client.connectionStatus?.state != MqttConnectionState.connected) return;
    try {
      client.publishMessage(
        latest.topic,
        MqttQos.atLeastOnce,
        (MqttClientPayloadBuilder()..addUTF8String(latest.payload)).payload!,
        retain: true,
      );
    } catch (error) {
      // The client reconnects by itself and sends the latest message then.
      debugPrint('MQTT publish failed: $error');
    }
  }

  Future<void> _connect() => _connecting ??= () async {
    _retry?.cancel();
    _setStatus(LinkState.connecting);
    try {
      final client = await connectToBroker(settings, role: 'scorer');
      if (_isClosed) return client.disconnect();
      client.onAutoReconnect = () => _setStatus(LinkState.offline, 'Connection lost. Reconnecting…');
      client.onAutoReconnected = () {
        _setStatus(LinkState.connected);
        _sendLatest();
      };
      _client = client;
      _setStatus(LinkState.connected);
      await _sendLatest();
    } catch (error) {
      debugPrint('MQTT connect failed: $error');
      _setStatus(LinkState.offline, '$error');
      // Keeps trying, so the latest score goes out as soon as the broker can be reached.
      if (!_isClosed) _retry = Timer(retryDelay, _connect);
    } finally {
      _connecting = null;
    }
  }();

  void close() {
    _isClosed = true;
    _retry?.cancel();
    _client?.disconnect();
    _client = null;
  }
}
