import 'package:flutter/material.dart';

import '../onboarding/sport.dart';
import '../widgets/choice_buttons.dart';
import 'match_setup.dart';

/// First match setup screen: format and game rules.
class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key, required this.sport, required this.onNext});

  final Sport sport;
  final void Function(BuildContext context, GameSetup game) onNext;

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  var _format = MatchFormat.doubles;
  var _bestOf = 3;
  var _gameTo = 11;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Game Setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Format'),
          ChoiceButtons(
            selected: _format,
            options: const {MatchFormat.singles: 'Singles', MatchFormat.doubles: 'Doubles'},
            onChanged: (v) => setState(() => _format = v),
          ),
          const SectionLabel('Match'),
          ChoiceButtons(
            selected: _bestOf,
            options: const {1: 'Best of 1', 3: 'Best of 3'},
            onChanged: (v) => setState(() => _bestOf = v),
          ),
          const SectionLabel('Game to'),
          ChoiceButtons(
            selected: _gameTo,
            options: const {11: '11', 15: '15', 21: '21'},
            onChanged: (v) => setState(() => _gameTo = v),
          ),
          const SizedBox(height: 8),
          Text(
            'Win by 2 · Side-out scoring',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => widget.onNext(
              context,
              GameSetup(sport: widget.sport, format: _format, bestOf: _bestOf, gameTo: _gameTo),
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
