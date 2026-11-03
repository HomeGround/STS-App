import 'package:flutter/material.dart';

/// A full-screen celebration of the match winner, with the match's numbers.
Future<void> showWinnerSplash(
  BuildContext context, {
  required String winnerName,
  required List<String> players,
  required int winnerSide,
  required List<List<int>> finishedGames,
  required Duration? duration,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (context, _, _) => _WinnerSplash(
      winnerName: winnerName,
      players: players,
      winnerSide: winnerSide,
      finishedGames: finishedGames,
      duration: duration,
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _WinnerSplash extends StatelessWidget {
  const _WinnerSplash({
    required this.winnerName,
    required this.players,
    required this.winnerSide,
    required this.finishedGames,
    required this.duration,
  });

  final String winnerName;
  final List<String> players;
  final int winnerSide;
  final List<List<int>> finishedGames;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final onSplash = colors.onPrimary;

    // Every figure is shown winner first.
    int winnerOf(List<int> score) => score[winnerSide - 1];
    int loserOf(List<int> score) => score[2 - winnerSide];
    final gamesWon = finishedGames.where((g) => winnerOf(g) > loserOf(g)).length;
    final pointsFor = finishedGames.fold(0, (sum, g) => sum + winnerOf(g));
    final pointsAgainst = finishedGames.fold(0, (sum, g) => sum + loserOf(g));

    return Material(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primary, Color.lerp(colors.primary, Colors.black, 0.35)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events, size: 72, color: onSplash),
                    const SizedBox(height: 8),
                    Text('MATCH WON', style: text.labelLarge?.copyWith(color: onSplash, letterSpacing: 6)),
                    const SizedBox(height: 4),
                    Text(
                      winnerName,
                      textAlign: TextAlign.center,
                      style: text.displayMedium?.copyWith(color: onSplash, fontWeight: FontWeight.w900),
                    ),
                    Text(players.join(' & '), style: text.titleMedium?.copyWith(color: onSplash)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Stat(label: 'Games', value: '$gamesWon–${finishedGames.length - gamesWon}', color: onSplash),
                        _Stat(label: 'Points', value: '$pointsFor–$pointsAgainst', color: onSplash),
                        if (duration != null) _Stat(label: 'Time', value: '${duration!.inMinutes} min', color: onSplash),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      [for (final (i, g) in finishedGames.indexed) 'G${i + 1}  ${winnerOf(g)}–${loserOf(g)}'].join('     '),
                      style: text.bodyLarge?.copyWith(color: onSplash),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: onSplash, foregroundColor: colors.primary),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(value, style: text.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
          Text(label.toUpperCase(), style: text.labelSmall?.copyWith(color: color, letterSpacing: 2)),
        ],
      ),
    );
  }
}
