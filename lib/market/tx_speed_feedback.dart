/// Pure-Dart high-speed presentation and verified-throughput instrumentation.
///
/// No prices, fills or simulated minutes are generated here. A desired speed
/// is never reported as achieved: throughput consumes *committed* steps only.
/// This module is experimental and deliberately has no database dependencies.
class TxSpeedViewPolicy {
  const TxSpeedViewPolicy._();

  static const List<int> supportedMinutePeriods = <int>[
    1, 5, 15, 60, 240, 1440,
  ];

  /// Aim for at least [minimumFramesPerBar] display frames per bar. A 60-Hz
  /// display gives about 36 frames per 1m candle at 100x, only one at 3600x.
  /// The policy only makes a chart-period recommendation; it NEVER aggregates
  /// or drops any economic event, and it must not silently override a user's
  /// manually selected period.
  static int suggestMinutes({
    required int requestedSpeed,
    required int refreshRateHz,
    int minimumFramesPerBar = 12,
  }) {
    if (requestedSpeed < 1 || refreshRateHz < 1 ||
        minimumFramesPerBar < 1) {
      throw ArgumentError('Invalid display policy inputs');
    }
    for (final period in supportedMinutePeriods) {
      // Exact integer cross multiplication, no floating point rounding.
      if (period * 60 * refreshRateHz >=
          requestedSpeed * minimumFramesPerBar) {
        return period;
      }
    }
    // Above the physical representability of one daily candle, the UI must
    // use sampled/range overview rather than pretend it can animate each bar.
    return supportedMinutePeriods.last;
  }

  static double estimatedFramesPerBar({
    required int requestedSpeed,
    required int refreshRateHz,
    required int periodMinutes,
  }) {
    if (requestedSpeed < 1 || refreshRateHz < 1 || periodMinutes < 1) {
      throw ArgumentError('Invalid display frame budget');
    }
    return periodMinutes * 60 * refreshRateHz / requestedSpeed;
  }

  /// A >0 return says how many displayed bars a UI should coalesce or sample
  /// at the selected maximum period, for diagnostic labels only. Zero means
  /// no sampling is indicated. The authoritative ledger remains unaltered.
  static int additionalSampleStride({
    required int requestedSpeed,
    required int refreshRateHz,
    int minimumFramesPerBar = 12,
  }) {
    if (requestedSpeed < 1 || refreshRateHz < 1 ||
        minimumFramesPerBar < 1) {
      throw ArgumentError('Invalid sample budget');
    }
    final maxMinutes = supportedMinutePeriods.last;
    final framesNumerator = maxMinutes * 60 * refreshRateHz;
    final requiredNumerator = requestedSpeed * minimumFramesPerBar;
    if (requiredNumerator <= framesNumerator) return 0;
    return (requiredNumerator + framesNumerator - 1) ~/ framesNumerator;
  }
}

/// Memory-bounded speed feedback based solely on successfully committed game
/// minutes and a caller-owned monotonic elapsed millisecond clock.
class TxCommittedSpeedWindow {
  TxCommittedSpeedWindow({this.capacity = 64})
      : _times = List<int>.filled(capacity > 0 ? capacity : 0, 0),
        _minutes = List<int>.filled(capacity > 0 ? capacity : 0, 0) {
    if (capacity < 2) {
      throw ArgumentError.value(capacity, 'capacity', 'Minimum is two');
    }
  }

  final int capacity;
  final List<int> _times;
  final List<int> _minutes;
  int _count = 0;
  int _next = 0;

  int get sampleCount => _count;

  /// Call on resume/speed switch to avoid mixing independent time epochs.
  void reset() {
    _count = 0;
    _next = 0;
  }

  /// [minute] is the durable session step AFTER SQLite commit, not the
  /// speculative target from the speed planner. Use a baseline sample when
  /// playback starts; call again only after an authenticated commit.
  void record({required int elapsedMilliseconds, required int minute}) {
    if (elapsedMilliseconds < 0 || minute < 0) {
      throw ArgumentError('Invalid speed sample');
    }
    if (_count > 0) {
      final last = (_next + capacity - 1) % capacity;
      if (elapsedMilliseconds < _times[last] || minute < _minutes[last]) {
        throw StateError('Committed speed samples moved backwards');
      }
      if (elapsedMilliseconds == _times[last] && minute == _minutes[last]) {
        return;
      }
    }
    _times[_next] = elapsedMilliseconds;
    _minutes[_next] = minute;
    _next = (_next + 1) % capacity;
    if (_count < capacity) _count++;
  }

  /// Total verified game seconds / real seconds in the recorded interval.
  /// Not an FPS, forecast, or proof that requested speed was sustained.
  double get achievedMultiplier {
    if (_count < 2) return 0;
    final first = (_next - _count + capacity) % capacity;
    final last = (_next + capacity - 1) % capacity;
    final elapsed = _times[last] - _times[first];
    if (elapsed <= 0) return 0;
    final completed = _minutes[last] - _minutes[first];
    return completed * 60000 / elapsed;
  }
}

/// Enforce single-flight compute -> safe transactional write, with an immediate
/// pause. Pausing or changing speed invalidates speculative COMPUTATION; an
/// ALREADY STARTED write is allowed to finish atomically before reconcile.
/// None of these methods can interrupt or roll back a SQLite transaction.
enum TxBatchPhase { idle, computing, writing, faulted }

class TxSingleFlightBatchGate {
  bool _playing = false;
  TxBatchPhase _phase = TxBatchPhase.idle;
  int _epoch = 0;
  int _serial = 0;
  int _activeToken = 0;
  int _claimEpoch = 0;

  bool get playing => _playing;
  TxBatchPhase get phase => _phase;
  bool get isBusy => _phase == TxBatchPhase.computing ||
      _phase == TxBatchPhase.writing;

  void resume() {
    if (_phase == TxBatchPhase.faulted) {
      throw StateError('Faulted transaction; audit before resume');
    }
    // A pause is immediate, but resuming before an in-flight worker or
    // SQLite write settles would let a stale epoch masquerade as live.
    // Reconcile/discard the old work before the user starts another epoch.
    if (_phase != TxBatchPhase.idle) {
      throw StateError('Wait for outstanding work to reconcile before resume');
    }
    _playing = true;
  }

  void pause() {
    _playing = false;
    _epoch++; // A computed-but-not-written result is now stale.
  }

  /// A speed change invalidates the old proposal but does not interrupt an
  /// active SQLite write. Restart the monotonic clock epoch separately.
  void speedChanged() {
    // Unlike pause, speed switching is not permitted mid-transaction.
    // The UI must wait for the previous revision to become authoritative.
    if (_phase == TxBatchPhase.writing ||
        _phase == TxBatchPhase.faulted) {
      throw StateError('Cannot change speed during uncommitted write');
    }
    _epoch++;
  }

  /// Returns null rather than queueing a second compute Future.
  int? beginCompute() {
    if (!_playing || _phase != TxBatchPhase.idle) return null;
    _phase = TxBatchPhase.computing;
    _claimEpoch = _epoch;
    _activeToken = ++_serial;
    return _activeToken;
  }

  /// False means discard the worker proposal WITHOUT writing to storage.
  /// This method is called immediately before opening the atomic transaction.
  bool beginAtomicWrite(int token) {
    if (_phase != TxBatchPhase.computing || token != _activeToken) {
      throw StateError('Invalid proposed batch token');
    }
    if (!_playing || _epoch != _claimEpoch) {
      _phase = TxBatchPhase.idle;
      return false;
    }
    _phase = TxBatchPhase.writing;
    return true;
  }

  void discardCompute(int token) {
    if (_phase != TxBatchPhase.computing || token != _activeToken) {
      throw StateError('Invalid discarded batch token');
    }
    _phase = TxBatchPhase.idle;
  }

  /// Safe only once an unambiguous SQLite commit has succeeded and its
  /// resulting account state has been reconciled into the authoritative view.
  bool finishAtomicWrite(int token) {
    if (_phase != TxBatchPhase.writing || token != _activeToken) {
      throw StateError('Invalid completed transaction');
    }
    _phase = TxBatchPhase.idle;
    // A pause or speed change during the write invalidates the old
    // playback epoch even if a later action tried to enable playback.
    // The durable write is NOT rolled back; only auto-scheduling stops.
    return _playing && _epoch == _claimEpoch;
  }

  /// Any ambiguous write outcome disables playback. Never synthesize a
  /// rollback or resume without reopening and independently auditing storage.
  void storageFailed() {
    _playing = false;
    _epoch++;
    _phase = TxBatchPhase.faulted;
  }
}
