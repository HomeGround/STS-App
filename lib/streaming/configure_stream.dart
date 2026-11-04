import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/choice_buttons.dart';
import 'stream_settings.dart';
import 'ticker_snapshot.dart';

/// Before streaming: which match, where to stream it, and at what quality.
class ConfigureStreamScreen extends StatefulWidget {
  const ConfigureStreamScreen({super.key, required this.lookupMatch, required this.onOpen});

  /// Finds a match by its ID, such as `MatchFeed.lookup`. Null if no scorer has published it.
  final Future<TickerSnapshot?> Function(String matchId) lookupMatch;
  final void Function(BuildContext context, StreamSetup setup) onOpen;

  @override
  State<ConfigureStreamScreen> createState() => _ConfigureStreamScreenState();
}

class _ConfigureStreamScreenState extends State<ConfigureStreamScreen> {
  /// The stream key is remembered on this device, so it only has to be pasted once.
  static const _streamKeyPreference = 'stream_key';

  final _matchId = TextEditingController();
  final _streamKey = TextEditingController();
  var _quality = StreamQuality.hd1080;
  var _frameRate = 30;
  var _isChecking = false;
  String? _matchProblem;
  String? _streamKeyProblem;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_streamKeyPreference);
      if (mounted && saved != null && _streamKey.text.isEmpty) setState(() => _streamKey.text = saved);
    });
  }

  @override
  void dispose() {
    _matchId.dispose();
    _streamKey.dispose();
    super.dispose();
  }

  bool get _canOpen => _matchId.text.length == 8 && _streamKey.text.trim().isNotEmpty && !_isChecking;

  Future<void> _open() async {
    final destination = streamUrlFrom(_streamKey.text);
    setState(() {
      _streamKeyProblem = destination.problem;
      _matchProblem = null;
    });
    if (destination.url == null) return;

    setState(() => _isChecking = true);
    try {
      final match = await widget.lookupMatch(_matchId.text);
      if (!mounted) return;
      if (match == null) {
        setState(
          () => _matchProblem =
              'No match has the ID ${_matchId.text}. Check it on the scoring device, '
              'and that its scoring screen is open.',
        );
        return;
      }
      await (await SharedPreferences.getInstance()).setString(_streamKeyPreference, _streamKey.text.trim());
      if (!mounted) return;
      widget.onOpen(
        context,
        StreamSetup(match: match, url: destination.url!, quality: _quality, frameRate: _frameRate),
      );
    } catch (error) {
      debugPrint('Match lookup failed: $error');
      if (mounted) {
        setState(
          () => _matchProblem =
              "Couldn't reach the score server. Check this phone is on the same network as the server, then try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure Stream')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Match ID'),
          TextField(
            controller: _matchId,
            decoration: InputDecoration(
              hintText: 'K7P2QXAB',
              helperText: 'Shown at the top of the scoring screen',
              errorText: _matchProblem,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w600),
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              TextInputFormatter.withFunction(
                (_, value) => value.copyWith(text: value.text.toUpperCase()),
              ),
            ],
            onChanged: (_) => setState(() => _matchProblem = null),
          ),
          const SectionLabel('Stream key'),
          TextField(
            controller: _streamKey,
            decoration: InputDecoration(
              hintText: 'abcd-efgh-ijkl-mnop-qrst',
              helperText: 'From YouTube Studio, or a full rtmp:// address for another service',
              errorText: _streamKeyProblem,
              border: const OutlineInputBorder(),
            ),
            autocorrect: false,
            onChanged: (_) => setState(() => _streamKeyProblem = null),
          ),
          const SectionLabel('Quality'),
          ChoiceButtons(
            selected: _quality,
            options: {for (final quality in StreamQuality.values) quality: quality.label},
            onChanged: (v) => setState(() => _quality = v),
          ),
          const SectionLabel('Frame rate'),
          ChoiceButtons(
            selected: _frameRate,
            options: const {30: '30 fps', 60: '60 fps'},
            onChanged: (v) => setState(() => _frameRate = v),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _canOpen ? _open : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _isChecking
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.videocam),
            label: const Text('Open camera'),
          ),
        ],
      ),
    );
  }
}
