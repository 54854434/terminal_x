/// Frame-driven game clock used only for *provisional* intraminute display.
///
/// The engine and ledger still change only when the caller durably commits
/// one complete game minute. A frame may request at most ONE such commit.
/// A slow storage write therefore reduces achieved speed instead of skipping
/// minutes, fabricating fills, or accumulating an unbounded transaction queue.
///
/// This model is independent of Flutter/SQLite, so pause and timing semantics
/// can be unit-tested without a device timer. Feed monotonic elapsed durations,
/// not DateTime, and never feed time while the app is backgrounded.
class TxFlowFrame {
  const TxFlowFrame({
    required this.second,
    required this.fractionOfMinute,
    required this.needsMinuteCommit,
    required this.isWaitingForStorage,
  });

  final int second;
  final double fractionOfMinute;
  final bool needsMinuteCommit;
  final bool isWaitingForStorage;
}

class TxContinuousFlowClock {
  TxContinuousFlowClock({int speed = 1}) {
    setSpeed(speed);
  }

  static const int gameMicrosPerMinute = 60000000;
  static const int maxSupportedSpeed = 360000;
  // Initial UI rollout stays conservative; the engine model has no 60x ceiling.
  // 600x and 3600x need the as-yet-unshipped atomic multi-minute writer.
  // 120x is safe to expose with single-flight backpressure (it may slow down).
  static const List<int> uiSpeeds = [1, 2, 5, 10, 15, 30, 60, 100, 120];
  int _speed = 1;
  int _fractionalGameMicros = 0;
  bool _running = false;
  bool _awaitingCommit = false;
  bool _faulted = false;

  int get speed => _speed;
  int get second => _fractionalGameMicros ~/ 1000000;
  double get minuteProgress =>
      _fractionalGameMicros / gameMicrosPerMinute;
  bool get running => _running;
  bool get awaitingCommit => _awaitingCommit;
  bool get faulted => _faulted;

  void setSpeed(int speed) {
    if (speed < 1 || speed > maxSupportedSpeed) {
      throw ArgumentError.value(speed, 'speed');
    }
    // The outstanding minute is already bound to the speed/clock epoch at
    // which its economic computation started. Reconcile it before switching.
    if (_awaitingCommit || _faulted) {
      throw StateError('Cannot change speed during unresolved minute');
    }
    _speed = speed;
  }

  void resume() {
    if (_faulted) throw StateError('Storage fault; reopen and audit first');
    // UI pause can fire while a SQLite commit is underway. Resuming before
    // that in-flight write is verified could start a second unsafe epoch.
    if (_awaitingCommit) {
      throw StateError('Unresolved minute commit; cannot resume playback');
    }
    _running = true;
  }

  /// Pause is synchronous, even while SQLite is committing the last minute.
  /// Once an irreversible transaction has begun, the result must still be
  /// reconciled; pause stops scheduling the NEXT minute, not the transaction.
  void pause() => _running = false;

  /// Apply one elapsed UI frame. The caller immediately schedules a single
  /// atomic minute commit when [TxFlowFrame.needsMinuteCommit] is true.
  /// Progress never moves beyond the last durable minute while waiting.
  TxFlowFrame advance(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed');
    }
    if (!_running || _awaitingCommit || _faulted) return _frame(false);
    final gameMicros = elapsed.inMicroseconds * _speed;
    if (gameMicros <= 0) return _frame(false);
    if (gameMicros >= gameMicrosPerMinute - _fractionalGameMicros) {
      // Hold the provisional candle at 59.999999 seconds while the account,
      // fills, and completed minute are being verified and committed.
      _fractionalGameMicros = gameMicrosPerMinute - 1;
      _awaitingCommit = true;
      return _frame(true);
    }
    _fractionalGameMicros += gameMicros;
    return _frame(false);
  }

  /// Call this ONLY after a verified SQLite transaction has committed.
  /// If the user pressed pause during the write, remain paused at second 0
  /// of the now-authoritative next minute; never start the next timer.
  void completeMinuteCommit() {
    if (!_awaitingCommit || _faulted) {
      throw StateError('No outstanding safe minute boundary');
    }
    _fractionalGameMicros = 0;
    _awaitingCommit = false;
  }

  /// Treat ambiguous outcomes as fatal, even when the caller thinks the DB
  /// might have rolled back. Never issue another order until reload/audit.
  void storageFailed() {
    _running = false;
    _faulted = true;
    _awaitingCommit = false;
  }

  TxFlowFrame _frame(bool newCommit) => TxFlowFrame(
    second: second,
    fractionOfMinute: minuteProgress,
    needsMinuteCommit: newCommit,
    isWaitingForStorage: _awaitingCommit,
  );
}

/// Bounded operational telemetry for one minute's worker+SQLite round-trip.
/// These samples are NOT UI FPS or the achieved game clock speed.
class TxCommitLatencyWindow {
  TxCommitLatencyWindow({this.capacity = 64})
      : _samples = List<int>.filled(capacity < 0 ? 0 : capacity, 0) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive');
    }
  }

  final int capacity;
  final List<int> _samples;
  int _next = 0;
  int _count = 0;

  int get count => _count;

  void add(Duration elapsed) {
    if (elapsed.isNegative) throw ArgumentError.value(elapsed, 'elapsed');
    _samples[_next] = elapsed.inMilliseconds;
    _next = (_next + 1) % capacity;
    if (_count < capacity) _count++;
  }

  /// Called only after commits, never by the per-frame Ticker callback.
  /// Constant storage, bounded O(capacity log capacity) selection.
  int get p95Milliseconds {
    if (_count == 0) return 0;
    final ordered = _samples.take(_count).toList()..sort();
    final rank = ((_count * 95 + 99) ~/ 100) - 1;
    return ordered[rank];
  }
}
