/// Non-gating, reproducible calculation baseline.
/// Run from repo root: dart run scripts/tx_chart_benchmark.dart
import 'dart:math' as math;
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_timeframe.dart';

void main() {
  final bars = List.generate(1500, (i) {
    final opening = 10000 + (i * 13) % 1200;
    final close = opening + i % 17 - 8;
    return TxCandle(step: i, openCents: opening,
        highCents: math.max(opening, close) + 3,
        lowCents: math.min(opening, close) - 3,
        closeCents: close, volumeShares: i % 21);
  });
  for (final p in [1, 5, 15, 60, 240, 1440]) {
    final stopwatch = Stopwatch()..start();
    for (var iteration = 0; iteration < 200; iteration++) {
      final result = TxTimeframe.aggregate(bars, p);
      if (result.bars.isEmpty) throw StateError('No bars');
    }
    stopwatch.stop();
    print('1500 minutes, $p minute buckets, 200 iterations: '
        '${stopwatch.elapsedMilliseconds}ms (local Dart only)');
  }
}
