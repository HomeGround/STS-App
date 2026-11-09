import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sts/config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads KEY=value lines, skipping comments and blanks and removing quotes', () {
    expect(
      parseEnv('# a comment\n\nSUPABASE_URL=https://x.supabase.co\nMQTT_PASSWORD="p@ss=word!"\r\n  MQTT_TLS = true \nbroken'),
      {'SUPABASE_URL': 'https://x.supabase.co', 'MQTT_PASSWORD': 'p@ss=word!', 'MQTT_TLS': 'true'},
    );
  });

  test('the bundled .env is loaded into the app', () async {
    expect(await rootBundle.loadString('.env'), isNotEmpty);
    final config = await AppConfig.load();
    for (final key in ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'MQTT_HOST', 'MQTT_PORT']) {
      expect(config[key], isNotEmpty, reason: '$key should come from .env');
    }
  });
}
