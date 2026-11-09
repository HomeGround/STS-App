import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config.dart';

/// Where the MQTT broker is. Set in .env and passed with `--dart-define-from-file=.env`.
class BrokerSettings {
  const BrokerSettings({required this.host, required this.port, this.username, this.password, this.useTls = false});

  /// From the app's settings (.env).
  factory BrokerSettings.fromConfig(AppConfig config) {
    String? optional(String key) => config[key].isEmpty ? null : config[key];
    return BrokerSettings(
      host: config['MQTT_HOST'],
      port: int.tryParse(config['MQTT_PORT']) ?? 1883,
      username: optional('MQTT_USERNAME'),
      password: optional('MQTT_PASSWORD'),
      useTls: config['MQTT_TLS'].toLowerCase() == 'true',
    );
  }

  /// From `--dart-define` values only, for tests run outside the app.
  factory BrokerSettings.fromEnvironment() {
    const username = String.fromEnvironment('MQTT_USERNAME');
    const password = String.fromEnvironment('MQTT_PASSWORD');
    return const BrokerSettings(
      host: String.fromEnvironment('MQTT_HOST'),
      port: int.fromEnvironment('MQTT_PORT', defaultValue: 1883),
      username: username == '' ? null : username,
      password: password == '' ? null : password,
      useTls: bool.fromEnvironment('MQTT_TLS'),
    );
  }

  final String host;
  final int port;
  final String? username;
  final String? password;

  /// Encrypted connections usually use port 8883.
  final bool useTls;
}

/// Each match has one topic. Its retained message is always the latest confirmed state of the match.
String matchTopic(String matchId) => 'scores/$matchId';

/// Connects to the broker, or throws [BrokerException]. The client reconnects by itself after a dropped connection.
Future<MqttServerClient> connectToBroker(BrokerSettings settings, {required String role}) async {
  if (settings.host.isEmpty) {
    throw const BrokerException('MQTT is not set up. Add MQTT_HOST to .env and run with --dart-define-from-file=.env.');
  }
  final clientId = 'sts-$role-${Random().nextInt(1 << 32).toRadixString(16)}';
  // One attempt, so a wrong address fails within the connect timeout; the caller decides when to try again.
  final client = MqttServerClient.withPort(settings.host, clientId, settings.port, maxConnectionAttempts: 1)
    ..keepAlivePeriod = 20
    ..connectTimeoutPeriod = 5000
    ..autoReconnect = true
    ..logging(on: false)
    ..setProtocolV311();
  if (settings.useTls) {
    client
      ..secure = true
      ..securityContext = SecurityContext.defaultContext;
  }
  try {
    final status = await client.connect(settings.username, settings.password);
    if (status?.state != MqttConnectionState.connected) throw StateError('not connected');
  } catch (error) {
    final refused = _refusal(client.connectionStatus?.returnCode);
    client.disconnect();
    // The underlying error says why: a wrong address, a blocked port, an encryption mismatch and so on.
    throw BrokerException(
      refused ??
          "Couldn't reach the score server at ${settings.host}:${settings.port}"
              "${settings.useTls ? ' (encrypted)' : ''}. $error",
    );
  }
  return client;
}

/// Why the broker turned the connection down, when it answered at all.
String? _refusal(MqttConnectReturnCode? code) => switch (code) {
  MqttConnectReturnCode.badUsernameOrPassword ||
  MqttConnectReturnCode.notAuthorized => 'The score server rejected the MQTT username or password.',
  MqttConnectReturnCode.brokerUnavailable => 'The score server is up but not accepting connections.',
  MqttConnectReturnCode.identifierRejected ||
  MqttConnectReturnCode.unacceptedProtocolVersion => 'The score server refused this app (${code!.name}).',
  _ => null,
};

class BrokerException implements Exception {
  const BrokerException(this.message);

  final String message;

  @override
  String toString() => message;
}
