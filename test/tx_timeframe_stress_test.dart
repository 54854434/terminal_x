import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_live_candles.dart';
import '../lib/market/tx_timeframe.dart';

void main() {
  test('1500 committed minutes aggregate with exact conservation', () {
    expect(TxLiveCandles.maxCandles, greaterThanOrEqualTo(1440));
    final source = List.generate(1500, (i) {
      final open = 1000 + i % 73;
      final close = open + (i % 7) - 3;
      return TxCandle(step: i, openCents: open, closeCents: close,
          highCents: math.max(open, close) + i % 4,
          lowCents: math.min(open, close) - i % 3,
          volumeShares: i % 9 == 0 ? 0 : i % 11 + 1);
    });
    final totalVolume = source.fold<int>(0, (total, b) =>
        total + b.volumeShares);
    for (final period in [1, 5, 15, 60, 240, 1440]) {
      final result = TxTimeframe.aggregate(source, period);
      expect(result.bars.fold<int>(0, (total, b) =>
          total + b.volumeShares), totalVolume);
      expect(result.hasGaps, isFalse);
      for (final bar in result.bars) {
        final covered = source.where((m) => m.step ~/ period ==
            bar.step ~/ period).toList();
        expect(bar.step, covered.first.step ~/ period * period);
        expect(bar.openCents, covered.first.openCents);
        expect(bar.closeCents, covered.last.closeCents);
        expect(bar.highCents, covered.map((b) => b.highCents).reduce(math.max));
        expect(bar.lowCents, covered.map((b) => b.lowCents).reduce(math.min));
      }
    }
  });
}
