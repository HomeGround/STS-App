import 'package:supabase_flutter/supabase_flutter.dart';

import '../scoring/match_setup.dart';
import '../scoring/score_sync.dart';
import '../scoring_rules/pickleball_rules.dart';

/// Calls the database functions that create and change matches. The app never writes to the tables directly.
class GamesApi {
  const GamesApi();

  SupabaseClient get _client => Supabase.instance.client;

  /// Creates the match with its sides and players, and returns the match ID the database picked
  /// and the secret token this device needs to change the score.
  Future<CreatedGame> createGame(GameSetup game, List<SideSetup> sides) async {
    final result = await _client.rpc('create_game', params: {
      'p_sport': game.sport.key,
      'p_match_format': game.format.name,
      'p_format_config': {'best_of': game.bestOf},
      'p_scoring_config': {'type': 'side_out', 'game_to': game.gameTo, 'win_by': PickleballRules.winBy},
      // Who serves first is chosen on the Score screen at the start of each game.
      'p_service_config': <String, Object>{},
      'p_sides': [
        for (final side in sides)
          {
            'display_name': side.displayName,
            'players': [
              for (final player in side.players) {'first_name': player.firstName, 'last_name': player.lastName},
            ],
          },
      ],
    });
    final created = result as Map<String, dynamic>;
    return (id: created['id'] as String, scorerToken: created['scorer_token'] as String);
  }

  /// Records one scoring action. The database applies the rules and returns the match's new version and state.
  /// Sending the same `clientEventId` again is safe: the database recognises it and records nothing new.
  Future<SavedAction> applyAction(ActionRequest request) async {
    final result = await _client.rpc('apply_action', params: {
      'p_game_id': request.gameId,
      'p_scorer_token': request.scorerToken,
      'p_client_event_id': request.clientEventId,
      'p_expected_version': request.expectedVersion,
      'p_action': request.action,
      'p_occurred_at': request.occurredAt.toIso8601String(),
    });
    final saved = result as Map<String, dynamic>;
    return (version: (saved['version'] as num).toInt(), state: saved['state'] as Map<String, dynamic>);
  }
}
