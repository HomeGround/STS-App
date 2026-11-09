import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.current = await AppConfig.load();
  final url = config['SUPABASE_URL'];
  final key = config['SUPABASE_PUBLISHABLE_KEY'];
  if (url.isEmpty || key.isEmpty || url.contains('YOUR-PROJECT-REF')) {
    debugPrint('[startup] Supabase is not configured');
    return runApp(
      const _SetupProblem('Supabase is not configured. Copy .env.example to .env, fill it in, and run the app again.'),
    );
  }
  debugPrint('[startup] showing the first screen');
  runApp(const StsApp());

  // The database is only needed once a match is created, so the first screen doesn't wait for it.
  try {
    await Supabase.initialize(url: url, publishableKey: key).timeout(const Duration(seconds: 15));
    debugPrint('[startup] Supabase ready');
  } catch (error) {
    debugPrint('[startup] Supabase failed to start: $error');
  }
}

/// Shown instead of a blank screen when the app can't start.
class _SetupProblem extends StatelessWidget {
  const _SetupProblem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(32), child: Text(message, textAlign: TextAlign.center)),
        ),
      ),
    );
  }
}
