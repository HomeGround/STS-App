import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scoring_rules/pickleball_rules.dart';
import '../widgets/landscape_lock.dart';
import 'match_setup.dart';
import 'score_sync.dart';
import 'winner_splash.dart';

/// Records the match rally by rally. Asks who serves and receives first at the start of each game.
class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key, required this.match, required this.applyAction});

  final MatchSetup match;

  /// Saves each action to the database, such as `GamesApi.applyAction`.
  final ApplyAction applyAction;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> with LandscapeLock {
  late final _rules = PickleballRules(widget.match.game);
  final _actions = <ScoringAction>[];

  /// The screen shows each point straight away; this saves them to the database in the background.
  late final _sync = ScoreSync(
    gameId: widget.match.id,
    scorerToken: widget.match.scorerToken,
    applyAction: widget.applyAction,
  );

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  /// The first server and, in doubles, receiver picked for the next game. Only recorded when the
  /// scorer presses Start, so they can still be changed (with undo) and the sides swapped until then.
  ({int side, int player})? _server;
  int? _receiver;

  bool get _isReadyToStart => _server != null && (!_rules.isDoubles || _receiver != null);

  /// Flips the sides on screen only, for when the scorer views the court from the other side.
  /// Real switches of ends are recorded as [SwitchEnds] actions.
  var _swapped = false;

  void _record(ScoringAction action) {
    final before = _rules.replay(_actions);
    setState(() => _actions.add(action));
    _sync.add(action.toJson());
    final after = _rules.replay(_actions);
    if (after.winner case final winner? when before.winner == null) {
      final side = widget.match.sides[winner - 1];
      showWinnerSplash(
        context,
        winnerName: side.displayName,
        players: [for (final player in side.players) player.displayName],
        winnerSide: winner,
        finishedGames: after.finishedGames,
        duration: _matchStartedAt == null ? null : DateTime.now().difference(_matchStartedAt!),
      );
    } else if (after.midpointReached && !before.midpointReached) {
      _ask(
        'Switch ends',
        'Midpoint of the deciding game. Teams, please switch ends.',
        actions: {'OK': () => _record(const SwitchEnds())},
      );
    } else if (after.game != before.game) {
      _ask(
        'Game ${before.game} is over',
        'Do the teams want to switch ends?',
        actions: {'No': () {}, 'Switch ends': () => _record(const SwitchEnds())},
      );
    }
  }

  /// Pauses scoring until the scorer picks one of [actions].
  void _ask(String title, String message, {required Map<String, VoidCallback> actions}) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        for (final MapEntry(key: label, value: onPressed) in actions.entries)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onPressed();
            },
            child: Text(label),
          ),
      ],
    ),
  );

  /// The streaming device needs this ID to show the match's ticker.
  Future<void> _copyMatchId() async {
    await Clipboard.setData(ClipboardData(text: widget.match.id));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Match ID copied')));
  }

  /// Steps back one thing at a time: the picked receiver, then the picked server, then recorded actions.
  /// Undoing a game's start brings back its picks and the Start button. Undoing an action is recorded
  /// as an event, so the database keeps the full history.
  void _undo() {
    if (_receiver != null) return setState(() => _receiver = null);
    if (_server != null) return setState(() => _server = null);
    setState(() {
      if (_actions.removeLast() case StartGame(:final servingSide, :final server, :final receiver)) {
        _server = (side: servingSide, player: server);
        if (_rules.isDoubles) _receiver = receiver;
      }
    });
    _sync.add({'type': 'undo'});
  }

  void _pickPlayer(int side, int player) => setState(() {
    if (_server == null) {
      _server = (side: side, player: player);
    } else {
      _receiver = player;
    }
  });

  /// When the first game was started, for the match time on the winner's splash.
  DateTime? _matchStartedAt;

  void _start() {
    _matchStartedAt ??= DateTime.now();
    final server = _server!;
    _record(StartGame(servingSide: server.side, server: server.player, receiver: _receiver ?? 1));
    _server = null;
    _receiver = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = _rules.replay(_actions);
    final sides = widget.match.sides;
    final text = Theme.of(context).textTheme;

    final server = _server;
    String name(int side, int player) => sides[side - 1].players[player - 1].displayName;

    final prompt = switch (state) {
      PickleballState(winner: final winner?) => '${sides[winner - 1].displayName} win the match',
      PickleballState(isAwaitingServe: true) => switch ((server, _receiver)) {
        (null, _) => 'Who serves first? Tap the player.',
        (_?, null) when _rules.isDoubles => 'Who receives first? Tap the player.',
        (final s?, final r?) => '${name(s.side, s.player)} serves to ${name(3 - s.side, r)}',
        (final s?, _) => '${name(s.side, s.player)} serves first',
      },
      _ => 'Tap the side that won the rally',
    };

    Widget panel(int side) {
      // While picking, the server can come from either side; the receiver must be on the other side.
      final canPick = state.isAwaitingServe && !_isReadyToStart && (server == null || server.side != side);
      return _SidePanel(
        side: sides[side - 1],
        score: state.score[side - 1],
        gamesWon: state.gamesWon[side - 1],
        server: state.servingSide == side ? state.server : null,
        serverNumber: state.serverNumber,
        isOnRight: (player) => state.isOnRight(side, player),
        isPicking: state.isAwaitingServe,
        pickedRoles: {
          if (server?.side == side) server!.player: 'serves',
          if (server != null && server.side != side && _receiver != null) _receiver!: 'receives',
        },
        onTap: state.winner == null && !state.isAwaitingServe ? () => _record(RallyWon(side)) : null,
        onPickPlayer: canPick ? (player) => _pickPlayer(side, player) : null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Game ${state.game}'),
        actions: [
          ListenableBuilder(listenable: _sync, builder: (context, _) => _SyncStatus(_sync)),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text('Match ID  ${widget.match.id}'),
            onPressed: _copyMatchId,
          ),
          // Sides can only be set up before a game starts. Undoing the start allows it again.
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Swap sides on screen',
            onPressed: state.isAwaitingServe ? () => setState(() => _swapped = !_swapped) : null,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _actions.isEmpty && _server == null ? null : _undo,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: panel(state.side1OnLeft != _swapped ? 1 : 2)),
                    const SizedBox(width: 16),
                    Expanded(child: panel(state.side1OnLeft != _swapped ? 2 : 1)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(state.call, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(prompt, style: text.bodyLarge),
              if (state.isAwaitingServe && _isReadyToStart) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('start-game'),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(state.game == 1 ? 'Start match' : 'Start game ${state.game}'),
                  onPressed: _start,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether every point is saved in the database. A point the database hasn't confirmed is never shown as saved.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus(this.sync);

  final ScoreSync sync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (sync.failure != null) {
      return TextButton.icon(
        icon: Icon(Icons.sync_problem, color: colors.error),
        label: Text('Not saved · Retry', style: TextStyle(color: colors.error)),
        onPressed: sync.retry,
      );
    }
    if (sync.waiting > 0) {
      return Tooltip(
        message: 'Waiting for the database to confirm',
        child: Chip(avatar: const Icon(Icons.cloud_upload_outlined, size: 18), label: Text('${sync.waiting} saving')),
      );
    }
    return const Tooltip(
      message: 'All points saved',
      child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.cloud_done_outlined)),
    );
  }
}

/// One side's name, score and players. Tapping it records that the side won the rally.
/// Before a game starts, its players are buttons for picking the first server and receiver.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.side,
    required this.score,
    required this.gamesWon,
    required this.server,
    required this.serverNumber,
    required this.isOnRight,
    required this.isPicking,
    required this.pickedRoles,
    required this.onTap,
    required this.onPickPlayer,
  });

  final SideSetup side;
  final int score;
  final int gamesWon;

  /// The serving player's position, if this side is serving.
  final int? server;
  final int? serverNumber;
  final bool Function(int player) isOnRight;

  /// Whether the game's first server and receiver are being picked.
  final bool isPicking;

  /// Picked players' positions and what they'll do, such as `{1: 'serves'}`.
  final Map<int, String> pickedRoles;
  final VoidCallback? onTap;

  /// Null when none of this side's players can be picked right now.
  final void Function(int player)? onPickPlayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card.filled(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: server != null ? BorderSide(color: colors.primary, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(side.displayName, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                  ),
                  Text('Games won $gamesWon', style: theme.textTheme.bodySmall),
                ],
              ),
              Expanded(
                child: FittedBox(
                  child: Text('$score', style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              for (final (i, player) in side.players.indexed)
                isPicking
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: pickedRoles[i + 1] != null
                            ? FilledButton.tonal(
                                onPressed: null,
                                style: FilledButton.styleFrom(
                                  disabledBackgroundColor: colors.primaryContainer,
                                  disabledForegroundColor: colors.onPrimaryContainer,
                                ),
                                child: Text('${player.displayName} · ${pickedRoles[i + 1]}'),
                              )
                            : OutlinedButton(
                                onPressed: onPickPlayer == null ? null : () => onPickPlayer!(i + 1),
                                child: Text(player.displayName),
                              ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: server == i + 1
                                  ? Icon(Icons.sports_baseball, size: 20, color: colors.primary)
                                  : null,
                            ),
                            Expanded(child: Text(player.displayName, overflow: TextOverflow.ellipsis)),
                            if (server == i + 1 && serverNumber != null)
                              Text('Server $serverNumber  ', style: TextStyle(color: colors.primary)),
                            Text(isOnRight(i + 1) ? 'Right' : 'Left', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}
