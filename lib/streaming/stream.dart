import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/landscape_lock.dart';
import 'stream_settings.dart';
import 'streamer.dart';
import 'ticker_snapshot.dart';

/// Films the match and streams it with the web ticker burned into the video.
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key, required this.setup, this.streamer = const Streamer()});

  final StreamSetup setup;
  final Streamer streamer;

  /// How often the ticker page is snapshotted while it changes, such as during its score animations.
  static const tickerFrameRate = 15;

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> with LandscapeLock {
  late final TickerSnapshot _match = widget.setup.match;
  var _isCameraReady = false;
  String? _cameraProblem;

  /// `idle`, `connecting`, `live` or `stopping`, as the native streamer reports it.
  var _state = 'idle';
  StreamSubscription<StreamerEvent>? _events;

  bool get _isOnAir => _state == 'live' || _state == 'connecting';

  @override
  void initState() {
    super.initState();
    _events = widget.streamer.events.listen(_onEvent);
    _openCamera();
  }

  @override
  void dispose() {
    _events?.cancel();
    widget.streamer.shutdown();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      await widget.streamer.start(widget.setup.quality, frameRate: widget.setup.frameRate);
      // The page follows the match over MQTT by itself, so the app doesn't need to send it scores.
      await widget.streamer.showWebTicker(webTickerPage(_match.id), fps: StreamScreen.tickerFrameRate);
      if (mounted) setState(() => _isCameraReady = true);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _cameraProblem = error.message);
    }
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
