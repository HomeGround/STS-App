import 'package:flutter_test/flutter_test.dart';
import 'package:sts/mqtt/broker.dart';

/// Connects with the app's own code and settings, then disconnects. Publishes nothing.
/// Skipped unless run with the app's settings: `flutter test test/mqtt/broker_connect_test.dart --dart-define-from-file=.env`
void main() {
  final settings = BrokerSettings.fromEnvironment();

  test('connects to the broker in .env', () async {
    final client = await connectToBroker(settings, role: 'test');
    client.disconnect();
  }, skip: settings.host.isEmpty ? 'Run with --dart-define-from-file=.env' : false);
}
