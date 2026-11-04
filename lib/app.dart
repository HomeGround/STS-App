import 'package:flutter/material.dart';

import 'backend/games_api.dart';
import 'mqtt/broker.dart';
import 'mqtt/match_broadcast.dart';
import 'mqtt/match_feed.dart';
import 'onboarding/role.dart';
import 'onboarding/select_sport_screen.dart';
import 'scoring/game_setup.dart';
import 'scoring/score.dart';
import 'scoring/team_details.dart';
import 'streaming/configure_stream.dart';
import 'streaming/stream.dart';

const _brandOrange = Color(0xFFED9440);

/// The scorer saves to the database and publishes to MQTT; the streamer only reads MQTT.
final _broker = BrokerSettings.fromEnvironment();
final _broadcast = MatchBroadcast(_broker);
final _feed = MatchFeed(_broker);

class StsApp extends StatelessWidget {
  const StsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STS',
      debugShowCheckedModeBanner: false,
      // Scoring and streaming both happen courtside over camera screens, so the app is dark throughout.
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandOrange,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
      ),
      home: SelectSportScreen(
        onSportSelected: (context, sport) => _push(
          context,
          RoleScreen(
            sport: sport,
            onScore: (context) => _push(
              context,
              GameSetupScreen(
                sport: sport,
                onNext: (context, game) => _push(
                  context,
                  TeamDetailsScreen(
                    game: game,
                    createGame: const GamesApi().createGame,
                    onStart: (context, match) => _push(
                      context,
                      ScoreScreen(
                        match: match,
                        applyAction: const GamesApi().applyAction,
                        broadcast: _broadcast.publish,
                        streamLink: _broadcast.status,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            onStream: (context) => _push(
              context,
              ConfigureStreamScreen(
                lookupMatch: _feed.lookup,
                onOpen: (context, setup) => _push(context, StreamScreen(setup: setup, watchMatch: _feed.watch)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}
