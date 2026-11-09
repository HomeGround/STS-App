import 'package:flutter/services.dart';

/// The app's settings: Supabase and the MQTT broker, from .env.
///
/// .env is bundled into the app as an asset, so every way of running it gets the settings: Xcode,
/// VS Code and `flutter run`. A value passed with `--dart-define` or `--dart-define-from-file` wins over the file.
class AppConfig {
  const AppConfig(this._values);

  /// Set once in `main` before the app starts.
  static AppConfig current = const AppConfig({});

  final Map<String, String> _values;

  static Future<AppConfig> load() async {
    final values = <String, String>{};
    try {
      values.addAll(parseEnv(await rootBundle.loadString('.env')));
    } catch (_) {
      // No bundled .env: only the --dart-define values below.
    }
    for (final (key, value) in _defines) {
      if (value.isNotEmpty) values[key] = value;
    }
    return AppConfig(values);
  }

  /// `String.fromEnvironment` only works with literal names, so each setting is listed here.
  static const _defines = [
    ('SUPABASE_URL', String.fromEnvironment('SUPABASE_URL')),
    ('SUPABASE_PUBLISHABLE_KEY', String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY')),
    ('MQTT_HOST', String.fromEnvironment('MQTT_HOST')),
    ('MQTT_PORT', String.fromEnvironment('MQTT_PORT')),
    ('MQTT_USERNAME', String.fromEnvironment('MQTT_USERNAME')),
    ('MQTT_PASSWORD', String.fromEnvironment('MQTT_PASSWORD')),
    ('MQTT_TLS', String.fromEnvironment('MQTT_TLS')),
  ];

  /// The setting, or an empty string if it isn't set.
  String operator [](String key) => _values[key] ?? '';
}

/// Reads `KEY=value` lines. Blank lines and lines starting with `#` are skipped, and quotes around a value are removed.
Map<String, String> parseEnv(String text) {
  final values = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final equals = line.indexOf('=');
    if (line.isEmpty || line.startsWith('#') || equals < 1) continue;
    var value = line.substring(equals + 1).trim();
    if (value.length >= 2 && (value[0] == '"' || value[0] == "'") && value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1);
    }
    values[line.substring(0, equals).trim()] = value;
  }
  return values;
}
