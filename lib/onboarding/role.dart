import 'package:flutter/material.dart';

import '../widgets/option_tile.dart';
import 'sport.dart';

/// Second screen: choose whether this device keeps score or streams the match.
class RoleScreen extends StatelessWidget {
  const RoleScreen({
    super.key,
    required this.sport,
    required this.onScore,
    required this.onStream,
  });

  final Sport sport;
  final void Function(BuildContext context) onScore;
  final void Function(BuildContext context) onStream;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(sport.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('What are you doing on this device?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: OptionTile(
              icon: Icons.scoreboard_outlined,
              label: 'Score',
              caption: 'Set up match, record points',
              onTap: () => onScore(context),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: OptionTile(
              icon: Icons.videocam_outlined,
              label: 'Stream',
              caption: 'Go live with score overlay',
              onTap: () => onStream(context),
            ),
          ),
        ],
      ),
    );
  }
}
