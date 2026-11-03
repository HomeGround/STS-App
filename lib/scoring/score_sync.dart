import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// One action to send to the database, as `GamesApi.applyAction` takes it.
typedef ActionRequest = ({
  String gameId,
  String scorerToken,
  String clientEventId,
  int expectedVersion,
  Map<String, Object?> action,
  DateTime occurredAt,
});

/// Saves an action and returns the match's new version.
typedef ApplyAction = Future<int> Function(ActionRequest request);

/// Sends the scorer's actions to the database one at a time, in the order they were recorded.
///
/// Each action keeps its `client_event_id` across retries, so the database never records it twice.
/// If an action fails, sending stops until [retry], because every later point depends on the earlier ones.
class ScoreSync extends ChangeNotifier {
  ScoreSync({required this.gameId, required this.scorerToken, required ApplyAction applyAction})
      : _applyAction = applyAction;

  final String gameId;
  final String scorerToken;
  final ApplyAction _applyAction;

  final _waiting = <({String clientEventId, Map<String, Object?> action, DateTime occurredAt})>[];

  /// The match's version in the database. A new match is at 0, its `game_created` event.
  var _version = 0;
  var _isSending = false;
  var _isDisposed = false;

  /// Why the last send failed, while sending is stopped.
  Object? failure;

  /// Actions recorded on this device but not yet confirmed by the database.
  int get waiting => _waiting.length;

  void add(Map<String, Object?> action) {
    _waiting.add((clientEventId: const Uuid().v4(), action: action, occurredAt: DateTime.now().toUtc()));
    notifyListeners();
    _send();
  }

  void retry() {
    failure = null;
    notifyListeners();
    _send();
  }

  Future<void> _send() async {
    if (_isSending || failure != null) return;
    _isSending = true;
    try {
      while (_waiting.isNotEmpty && !_isDisposed) {
        final next = _waiting.first;
        _version = await _applyAction((
          gameId: gameId,
          scorerToken: scorerToken,
          clientEventId: next.clientEventId,
          expectedVersion: _version,
          action: next.action,
          occurredAt: next.occurredAt,
        ));
        _waiting.removeAt(0);
        if (!_isDisposed) notifyListeners();
      }
    } catch (error) {
      debugPrint('apply_action failed: $error');
      failure = error;
      if (!_isDisposed) notifyListeners();
    } finally {
      _isSending = false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
