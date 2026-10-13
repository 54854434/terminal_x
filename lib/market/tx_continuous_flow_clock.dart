/// Frame-driven game clock used only for *provisional* intraminute display.
///
/// A real NPC pulse or complete minute becomes a playback candidate after its
/// isolated worker finishes; it becomes the recovery authority only AFTER its
/// SQLite revision commits. At most one request may be in flight.
/// Slow storage lowers achieved speed; the clock never skips ledger minutes,
/// fabricates fills, or creates an unbounded transaction queue.
///
/// This model is independent of Flutter/SQLite, so pause and timing semantics
/// can be unit-tested without a device timer. Feed monotonic elapsed durations,
/// not DateTime, and never feed time while the app is backgrounded.
class TxFlowFrame {
  const TxFlowFrame({
    required this.second,
    required this.fractionOfMinute,
    required this.needsMinuteCommit,
    required this.needsPulseCommit,
    required this.isWaitingForStorage,
  });

  final int second;
  final double fractionOfMinute;
  final bool needsMinuteCommit;
  /// A verified Rust market pulse, not a completed game-minute boundary.
  final bool needsPulseCommit;
  final bool isWaitingForStorage;
}

class TxContinuousFlowClock {
  TxContinuousFlowClock({int speed = 1, int pulseSeconds = 60}) {
    setSpeed(speed);
    setPulseSeconds(pulseSeconds);
  }

  static const int gameMicrosPerMinute = 60000000;
  static const int maxSupportedSpeed = 360000;
  // Requested target rates only: single-flight SQLite commits determine
  // ACTUAL achieved speed. Fast targets never skip economic minutes.
  static const List<int> uiSpeeds = [1, 2, 5, 10, 15, 30, 60, 100, 120, 300, 600, 1200, 3600];
  int _speed = 1;
  int _pulseSeconds = 60;
  int _fractionalGameMicros = 0;
  bool _running = false;
  bool _awaitingCommit = false;
  bool _faulted = false;

  int get speed => _speed;
  int get pulseSeconds => _pulseSeconds;
  int get second => _fractionalGameMicros ~/ 1000000;

  /// 60 disables intraminute execution. The new cadence is applied only
  /// between completed SQLite revisions; nothing is committed on a timer.
  void setPulseSeconds(int seconds) {
    if (seconds < 5 || seconds > 60) {
      throw ArgumentError.value(seconds, 'pulseSeconds');
    }
    if (_awaitingCommit || _faulted) {
      throw StateError('Cannot change pulse cadence during an unresolved commit');
    }
    _pulseSeconds = seconds;
  }
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

  /// Drop uncommitted visual seconds for an explicit manual minute step.
  /// This is NOT a ledger rollback; committed state is never touched.
  void resetProvisional() {
    if (_running || _awaitingCommit || _faulted) {
      throw StateError('Cannot rebase running or unresolved game time');
    }
    _fractionalGameMicros = 0;
  }

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
    final pulseMicros = _pulseSeconds * 1000000;
    final nextPulse = ((_fractionalGameMicros ~/ pulseMicros) + 1) * pulseMicros;
    final boundary = nextPulse < gameMicrosPerMinute
        ? nextPulse : gameMicrosPerMinute;
    if (gameMicros >= boundary - _fractionalGameMicros) {
      _awaitingCommit = true;
      if (boundary == gameMicrosPerMinute) {
        // No economic time advances past the unverified final revision.
        _fractionalGameMicros = gameMicrosPerMinute - 1;
        return _frame(true);
      }
      _fractionalGameMicros = boundary;
      return _frame(false, pulse: true);
    }
    _fractionalGameMicros += gameMicros;
    return _frame(false);
  }

  /// Call this after the isolated minute candidate has been accepted. When
  /// automatic persistence is deferred, the candidate remains explicitly
  /// pending in SQLite and lifecycle/player actions must flush it.
  void completeMinuteCommit() {
    if (!_awaitingCommit || _faulted) {
      throw StateError('No outstanding safe minute boundary');
    }
    _fractionalGameMicros = 0;
    _awaitingCommit = false;
  }

  /// A real intraminute Rust order-book candidate has been accepted. Unlike a
  /// finished minute, preserve the clock position for the next pulse.
  void completePulseCommit() {
    if (!_awaitingCommit || _faulted ||
        _fractionalGameMicros <= 0 ||
        _fractionalGameMicros >= gameMicrosPerMinute - 1) {
      throw StateError('No pending intraminute market pulse');
    }
    _awaitingCommit = false;
  }

  /// Treat ambiguous outcomes as fatal, even when the caller thinks the DB
  /// might have rolled back. Never issue another order until reload/audit.
  void storageFailed() {
    _running = false;
    _faulted = true;
    _awaitingCommit = false;
  }

  TxFlowFrame _frame(bool newCommit, {bool pulse = false}) => TxFlowFrame(
    second: second,
    fractionOfMinute: minuteProgress,
    needsMinuteCommit: newCommit,
    needsPulseCommit: pulse,
    isWaitingForStorage: _awaitingCommit,
  );
}

/// Display-only motion used while an already-reached boundary is being
/// verified and written. It never advances [TxContinuousFlowClock], changes a
/// price, or authorizes another market operation. Keeping this calculation
/// independent lets the UI show that safe settlement is active without
/// presenting uncommitted game time as durable state.
class TxSettlementMotion {
  const TxSettlementMotion._();

  static const Duration cycle = Duration(milliseconds: 720);

  static double phase(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed');
    }
    final cycleMicros = cycle.inMicroseconds;
    if (cycleMicros <= 0) {
      throw StateError('Invalid settlement animation cycle');
    }
    return (elapsed.inMicroseconds % cycleMicros) / cycleMicros;
  }
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
