import 'dart:math' as math;

import 'tx_candle_history.dart';

/// Deterministic *indicative* frame price; has no fills, volume or ledger.
/// Uses fractional game seconds so 1x playback also repaints smoothly.
class TxFrameQuote {
  const TxFrameQuote._();

  static double cents(int committedCents, int minute,
      double seconds, int symbolIndex) {
    if (committedCents < 1 || minute < 0 || !seconds.isFinite ||
        seconds < 0 || seconds >= 60 || symbolIndex < 0) {
      throw ArgumentError('Invalid indicative frame quote input');
    }
    if (seconds == 0) return committedCents.toDouble();
    final amplitude = math.max(2, (committedCents / 190).round());
    final phase = minute * .83 + symbolIndex * 1.93;
    final move = amplitude * (
        .68 * (math.sin(seconds * .28 + phase) - math.sin(phase)) +
        .32 * (math.sin(seconds * .79 + phase * 2) -
            math.sin(phase * 2)));
    return math.max(1.0, committedCents + move);
  }
}

/// Project a cyan preview onto its *current* timeframe bucket. The source
/// TxCandle remains unchanged: OHLCV, MA and historical inspection stay
/// exclusively derived from verified committed minutes.
class TxFrameCandleProjection {
  const TxFrameCandleProjection({
    required this.groupStep,
    required this.overlaysLastCommitted,
    required this.openCents,
    required this.highCents,
    required this.lowCents,
    required this.closeCents,
  });

  final int groupStep;
  final bool overlaysLastCommitted;
  final double openCents, highCents, lowCents, closeCents;

  static TxFrameCandleProjection fromLastCommitted({
    required TxCandle lastAggregated,
    required int nextMinuteStep,
    required int periodMinutes,
    required double framePriceCents,
    required double previewHighCents,
    required double previewLowCents,
  }) {
    if (nextMinuteStep < 0 || periodMinutes < 1 ||
        !framePriceCents.isFinite || !previewHighCents.isFinite ||
        !previewLowCents.isFinite || previewLowCents <= 0 ||
        previewLowCents > framePriceCents ||
        previewHighCents < framePriceCents) {
      throw ArgumentError('Invalid preview projection');
    }
    final group = nextMinuteStep ~/ periodMinutes * periodMinutes;
    if (lastAggregated.step > group) {
      throw StateError('Committed aggregation is ahead of preview clock');
    }
    final sameGroup = lastAggregated.step == group;
    final open = sameGroup
        ? lastAggregated.openCents.toDouble()
        : lastAggregated.closeCents.toDouble();
    final high = math.max(math.max(open, previewHighCents),
        sameGroup ? lastAggregated.highCents.toDouble() : open);
    final low = math.min(math.min(open, previewLowCents),
        sameGroup ? lastAggregated.lowCents.toDouble() : open);
    return TxFrameCandleProjection(
      groupStep: group,
      overlaysLastCommitted: sameGroup,
      openCents: open,
      highCents: high,
      lowCents: low,
      closeCents: framePriceCents,
    );
  }
}

/// Visual-only intrabucket quote envelope. A provisional quote is NOT an
/// executed fill, and these values are deliberately never serialized into
/// committed OHLC, trade history, or SQLite snapshots.
///
/// A 5m/15m/... bar must not lose its cyan intrabar high/low merely because
/// the previous one-minute SQLite revision completed. Reset at the actual
/// timeframe bucket rollover, symbol switch or period switch instead.
class TxIndicativeWickMemory {
  int? _groupStep;
  double? _high;
  double? _low;

  int? get groupStep => _groupStep;
  double? get highCents => _high;
  double? get lowCents => _low;

  void reset() {
    _groupStep = null;
    _high = null;
    _low = null;
  }

  void observe({
    required int nextMinuteStep,
    required int periodMinutes,
    required double committedCloseCents,
    double? framePriceCents,
  }) {
    if (nextMinuteStep < 0 || periodMinutes < 1 ||
        !committedCloseCents.isFinite || committedCloseCents <= 0 ||
        (framePriceCents != null &&
            (!framePriceCents.isFinite || framePriceCents <= 0))) {
      throw ArgumentError('Invalid indicative envelope input');
    }
    final group = (nextMinuteStep ~/ periodMinutes) * periodMinutes;
    if (group != _groupStep) {
      _groupStep = group;
      _high = committedCloseCents;
      _low = committedCloseCents;
    }
    if (framePriceCents != null) {
      _high = math.max(_high!, framePriceCents);
      _low = math.min(_low!, framePriceCents);
    }
  }
}


/// A bounded continuous intraminute line segment. This is a *visual quote*
/// only: no fill, bid, ask, volume, ledger entry or SQLite revision is created.
/// Reinitialize from the verified last close when the next committed minute
/// arrives, or if the playback clock explicitly rebases backwards.
class TxTimelineTracePoint {
  const TxTimelineTracePoint(this.seconds, this.priceCents);
  final double seconds;
  final double priceCents;
}

class TxTimelinePreviewTrace {
  int? _minute;
  final List<TxTimelineTracePoint> _points = [];
  int? get minute => _minute;
  List<TxTimelineTracePoint> get points =>
      List<TxTimelineTracePoint>.unmodifiable(_points);

  void reset() {
    _minute = null;
    _points.clear();
  }

  void observe({required int nextMinuteStep,
      required double seconds, required double committedCloseCents,
      required double framePriceCents}) {
    if (nextMinuteStep < 0 || !seconds.isFinite || seconds < 0 || seconds >= 60 ||
        !committedCloseCents.isFinite || committedCloseCents < 1 ||
        !framePriceCents.isFinite || framePriceCents < 1) {
      throw ArgumentError('Invalid timeline preview sample');
    }
    if (_minute != nextMinuteStep ||
        (_points.isNotEmpty && seconds < _points.last.seconds)) {
      _minute = nextMinuteStep;
      _points..clear()..add(TxTimelineTracePoint(0, committedCloseCents));
    }
    if (_points.last.seconds == seconds) {
      _points[_points.length - 1] = TxTimelineTracePoint(seconds,
          seconds == 0 ? committedCloseCents : framePriceCents);
    } else {
      _points.add(TxTimelineTracePoint(seconds, framePriceCents));
    }
    // Keep bounded memory even after hours paused on a one-minute boundary.
    // Preserve the true start and newest point, decimate the middle only.
    if (_points.length > 192) {
      final old = List<TxTimelineTracePoint>.of(_points);
      _points.clear();
      _points.add(old.first);
      for (var i = 2; i < old.length - 1; i += 2) {
        _points.add(old[i]);
      }
      _points.add(old.last);
    }
  }
}
