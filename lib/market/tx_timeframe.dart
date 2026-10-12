import 'dart:math' as math;

import 'tx_candle_history.dart';

/// These intervals group already committed one-minute bars. They are not
/// evidence of intraminute trades, and never fill missing minutes with prices.
enum TxChartPeriod {
  timeline(0, '分时'),
  oneMinute(1, '1分'),
  fiveMinutes(5, '5分'),
  fifteenMinutes(15, '15分'),
  oneHour(60, '1时'),
  fourHours(240, '4时'),
  oneDay(1440, '1日');

  const TxChartPeriod(this.minutes, this.label);
  final int minutes;
  final String label;
}

class TxAggregatedBars {
  const TxAggregatedBars({
    required this.bars,
    required this.leftIncomplete,
    required this.rightIncomplete,
    required this.hasGaps,
  });
  final List<TxCandle> bars;
  /// History starts in the middle of an interval (e.g. on app reopen).
  final bool leftIncomplete;
  /// The most recent closed minute has not completed its larger interval.
  final bool rightIncomplete;
  /// Missing committed minute(s) cannot be invented to complete a bar.
  final bool hasGaps;
}

class TxTimeframe {
  const TxTimeframe._();

  static TxAggregatedBars aggregate(List<TxCandle> minutes, int periodMinutes) {
    if (periodMinutes < 1) throw ArgumentError.value(periodMinutes);
    if (minutes.isEmpty) {
      return const TxAggregatedBars(bars: <TxCandle>[],
          leftIncomplete: false, rightIncomplete: false, hasGaps: false);
    }
    for (var i = 1; i < minutes.length; i++) {
      if (minutes[i].step <= minutes[i - 1].step) {
        throw StateError('Source minute order is not strictly increasing');
      }
    }
    if (periodMinutes == 1) {
      return TxAggregatedBars(bars: minutes,
        leftIncomplete: false, rightIncomplete: false,
        hasGaps: _hasGap(minutes));
    }

    final result = <TxCandle>[];
    var lastGroup = -1;
    var gaps = false;
    for (var i = 0; i < minutes.length; i++) {
      final item = minutes[i];
      final group = item.step ~/ periodMinutes;
      if (i > 0 && item.step != minutes[i - 1].step + 1) gaps = true;
      if (group != lastGroup) {
        result.add(TxCandle(
          // The interval begins at this aligned game-minute boundary.
          step: group * periodMinutes,
          openCents: item.openCents,
          highCents: item.highCents,
          lowCents: item.lowCents,
          closeCents: item.closeCents,
          volumeShares: item.volumeShares,
        ));
        lastGroup = group;
      } else {
        final prev = result.removeLast();
        result.add(TxCandle(
          step: prev.step,
          openCents: prev.openCents,
          highCents: math.max(prev.highCents, item.highCents),
          lowCents: math.min(prev.lowCents, item.lowCents),
          closeCents: item.closeCents,
          volumeShares: prev.volumeShares + item.volumeShares,
        ));
      }
    }
    return TxAggregatedBars(
      bars: List<TxCandle>.unmodifiable(result),
      leftIncomplete: minutes.first.step % periodMinutes != 0,
      rightIncomplete: minutes.last.step % periodMinutes != periodMinutes - 1,
      hasGaps: gaps,
    );
  }

  static bool _hasGap(List<TxCandle> bars) {
    for (var i = 1; i < bars.length; i++) {
      if (bars[i].step != bars[i - 1].step + 1) return true;
    }
    return false;
  }
}
