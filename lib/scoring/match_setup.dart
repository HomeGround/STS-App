import '../onboarding/sport.dart';

/// Stored as `games.match_format`. Decides how many players each side has.
enum MatchFormat {
  singles(1),
  doubles(2);

  const MatchFormat(this.playersPerSide);

  final int playersPerSide;
}

/// The choices from the Game Setup screen. Win by 2 and side-out scoring are fixed in version 1.
class GameSetup {
  const GameSetup({
    required this.sport,
    required this.format,
    required this.bestOf,
    required this.gameTo,
  });

  final Sport sport;
  final MatchFormat format;
  final int bestOf;
  final int gameTo;
}

/// Stored as `game_participants.display_name`, with the two parts in `participant_config`.
class PlayerSetup {
  const PlayerSetup({required this.firstName, required this.lastName});

  final String firstName;
  final String lastName;

  String get displayName => '$firstName $lastName';
}

/// One side of the match, as entered on the Team Details screen.
class SideSetup {
  const SideSetup({required this.displayName, required this.players});

  /// Stored as `game_sides.display_name`.
  final String displayName;

  /// In their fixed order, stored as `game_participants.player_position` 1 and 2.
  final List<PlayerSetup> players;
}

/// Everything needed to create a match. Who serves first is chosen on the Score screen at the start of each game.
/// What the database returns for a new match.
typedef CreatedGame = ({String id, String scorerToken});

class MatchSetup {
  const MatchSetup({required this.id, required this.scorerToken, required this.game, required this.sides});

  /// The match ID, such as `K7P2QXAB`, picked by the database's `create_game` and stored as `games.id`.
  /// It is also the ticker ID typed on the streaming device.
  final String id;

  /// Proves this device is the match's scorer. Sent with every score change and never shown.
  /// The database keeps only its hash.
  final String scorerToken;

  final GameSetup game;

  /// Side 1 then side 2.
  final List<SideSetup> sides;
}
