import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/landscape_lock.dart';
import 'stream_settings.dart';
import 'streamer.dart';
import 'ticker_painter.dart';
import 'ticker_snapshot.dart';

/// Films the match and streams it with the live ticker burned into the video.
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key, required this.setup, required this.watchMatch, this.streamer = const Streamer()});

  final StreamSetup setup;

  /// Every update the scorer publishes for the match, such as `MatchFeed.watch`.
  final Stream<TickerSnapshot> Function(String matchId) watchMatch;
  final Streamer streamer;

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> with LandscapeLock {
  late TickerSnapshot _match = widget.setup.match;
  var _isCameraReady = false;
  String? _cameraProblem;

  /// `idle`, `connecting`, `live` or `stopping`, as the native streamer reports it.
  var _state = 'idle';
  StreamSubscription<StreamerEvent>? _events;
  StreamSubscription<TickerSnapshot>? _updates;

  /// Ticker redraws run one after another, so the last one always shows the newest score.
  var _drawing = Future<void>.value();

  bool get _isOnAir => _state == 'live' || _state == 'connecting';

  @override
  void initState() {
    super.initState();
    _events = widget.streamer.events.listen(_onEvent);
    _openCamera();
  }

  @override
  void dispose() {
    _updates?.cancel();
    _events?.cancel();
    widget.streamer.shutdown();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      await widget.streamer.start(widget.setup.quality, frameRate: widget.setup.frameRate);
      await _drawTicker();
      if (!mounted) return;
      setState(() => _isCameraReady = true);
      _updates = widget.watchMatch(_match.id).listen(
        _onUpdate,
        // The connection retries by itself; the ticker keeps the last score meanwhile.
        onError: (Object error) => debugPrint('Match updates failed: $error'),
      );
    } on PlatformException catch (error) {
      if (mounted) setState(() => _cameraProblem = error.message);
    }
  }

  /// Redraws the ticker for a newer score. Repeats and older messages are ignored.
  void _onUpdate(TickerSnapshot latest) {
    if (latest.version <= _match.version || !mounted) return;
    setState(() => _match = latest);
    _drawing = _drawing.then((_) => _drawTicker()).catchError((Object error) {
      debugPrint('Ticker redraw failed: $error');
    });
  }

  Future<void> _drawTicker() async {
    final quality = widget.setup.quality;
    await widget.streamer.setOverlay(await renderTicker(_match, width: quality.width, height: quality.height));
  }

  void _onEvent(StreamerEvent event) {
    setState(() => _state = event.state);
    if (event.error != null) _tell(event.error!);
  }

  Future<void> _goLive() async {
    try {
      await widget.streamer.goLive(widget.setup.url);
    } on PlatformException catch (error) {
      _tell(error.message ?? "Couldn't start the stream.");
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stream'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  /// Leaving while live ends the stream, so ask first.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End the stream?'),
        content: const Text('Leaving this screen ends the live stream.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep streaming')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End stream')),
        ],
      ),
    );
    if (leave == true && mounted) {
      await widget.streamer.stop();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final Widget preview = switch ((_cameraProblem, _isCameraReady)) {
      (final problem?, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(problem))),
      (_, false) => const Center(child: CircularProgressIndicator()),
      _ when defaultTargetPlatform != TargetPlatform.iOS =>
        const Center(child: Text('Streaming works on iPhone and iPad for now.')),
      _ => const UiKitView(viewType: Streamer.previewViewType),
    };

    final button = switch (_state) {
      'live' => FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
          onPressed: widget.streamer.stop,
          icon: const Icon(Icons.stop),
          label: const Text('End stream'),
        ),
      'connecting' => FilledButton.icon(
          onPressed: null,
          icon: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          label: const Text('Connecting…'),
        ),
      'stopping' => const FilledButton(onPressed: null, child: Text('Ending…')),
      _ => FilledButton.icon(
          onPressed: _isCameraReady ? _goLive : null,
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Go live'),
        ),
    };

    return PopScope(
      canPop: !_isOnAir,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Every child is positioned, so the stack fills the screen rather than shrinking to the top bar.
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: preview),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const BackButton(color: Colors.white),
                      Expanded(
                        child: Text(
                          '${_match.title}   ·   ${_match.id}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_state == 'live')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: colors.error, borderRadius: BorderRadius.circular(4)),
                          child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 24, child: Center(child: button)),
          ],
        ),
      ),
    );
  }
}
