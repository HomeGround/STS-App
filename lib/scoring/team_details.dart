import 'package:flutter/material.dart';

import '../widgets/choice_buttons.dart';
import '../widgets/landscape_lock.dart';
import 'match_setup.dart';

/// Second match setup screen: team and player names. Landscape gives each side its own column.
class TeamDetailsScreen extends StatefulWidget {
  const TeamDetailsScreen({super.key, required this.game, required this.createGame, required this.onStart});

  final GameSetup game;

  /// Saves the match and returns its ID and scorer token, such as `GamesApi.createGame`.
  final Future<CreatedGame> Function(GameSetup game, List<SideSetup> sides) createGame;
  final void Function(BuildContext context, MatchSetup match) onStart;

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> with LandscapeLock {
  final _teamNames = [TextEditingController(), TextEditingController()];
  late final _players = [
    for (var side = 0; side < 2; side++)
      [
        for (var i = 0; i < widget.game.format.playersPerSide; i++)
          (first: TextEditingController(), last: TextEditingController()),
      ],
  ];

  bool get _isDoubles => widget.game.format == MatchFormat.doubles;

  @override
  void dispose() {
    for (final controller in [..._teamNames, for (final p in _players.expand((side) => side)) ...[p.first, p.last]]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<PlayerSetup> _playersOf(int side) => [
        for (final p in _players[side]) PlayerSetup(firstName: p.first.text.trim(), lastName: p.last.text.trim()),
      ];

  bool get _canStart => [0, 1].every(
        (side) => _playersOf(side).every((p) => p.firstName.isNotEmpty && p.lastName.isNotEmpty),
      );

  /// The team name if one was typed, otherwise the players' last names, such as "Smith / Patel".
  /// A single player goes by their full name.
  String _sideName(int side) {
    final teamName = _teamNames[side].text.trim();
    final players = _playersOf(side);
    final name = _isDoubles
        ? (teamName.isNotEmpty ? teamName : players.map((p) => p.lastName).where((n) => n.isNotEmpty).join(' / '))
        : players.single.displayName.trim();
    return name.isEmpty ? 'Side ${side + 1}' : name;
  }

  var _isCreating = false;

  /// The match ID comes from the database, so starting a match needs a connection.
  Future<void> _start() async {
    final sides = [for (final side in [0, 1]) SideSetup(displayName: _sideName(side), players: _playersOf(side))];
    setState(() => _isCreating = true);
    try {
      final created = await widget.createGame(widget.game, sides);
      if (mounted) {
        widget.onStart(
          context,
          MatchSetup(id: created.id, scorerToken: created.scorerToken, game: widget.game, sides: sides),
        );
      }
    } catch (error) {
      // Shows the database's reason in the `flutter run` output; the scorer just sees the message below.
      debugPrint('create_game failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't create the match. Check the connection and try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _side(0)),
              const SizedBox(width: 24),
              Expanded(child: _side(1)),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _canStart && !_isCreating ? _start : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _isCreating
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Start Match'),
          ),
        ],
      ),
    );
  }

  Widget _side(int side) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Side ${side + 1}'),
          if (_isDoubles) _field(_teamNames[side], 'Team name (optional)'),
          for (final p in _players[side])
            Row(
              children: [
                Expanded(child: _field(p.first, 'First name')),
                const SizedBox(width: 8),
                Expanded(child: _field(p.last, 'Last name')),
              ],
            ),
        ],
      );

  Widget _field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
      );
}
