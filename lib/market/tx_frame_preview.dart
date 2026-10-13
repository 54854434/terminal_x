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
