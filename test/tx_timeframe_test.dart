import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_timeframe.dart';

TxCandle sample(int minute, int open, int close, int high, int low, int volume) =>
    TxCandle(step: minute, openCents: open, closeCents: close,
      highCents: high, lowCents: low, volumeShares: volume);

void main() {
  test('5m OHLCV uses first open, last close, real extrema and sum volume', () {
    final source = <TxCandle>[
      sample(0,100,102,103,99,5),
      sample(1,102,101,104,100,0),
      sample(2,101,105,107,98,7),
      sample(3,105,100,105,100,2),
      sample(4,100,103,104,100,8),
      sample(5,103,107,108,103,3),
    ];
    final frame = TxTimeframe.aggregate(source, 5);
    expect(frame.bars.length, 2);
    expect(frame.bars.first.step, 0);
    expect(frame.bars.first.openCents, 100);
    expect(frame.bars.first.closeCents, 103);
    expect(frame.bars.first.highCents, 107);
    expect(frame.bars.first.lowCents, 98);
    expect(frame.bars.first.volumeShares, 22);
    expect(frame.bars.last.volumeShares, 3);
    expect(frame.leftIncomplete, isFalse);
    expect(frame.rightIncomplete, isTrue);
    expect(frame.hasGaps, isFalse);
  });

  test('15m, 1h and 4h align to game minute boundaries', () {
    final source = List.generate(300, (i) => sample(
      i, 1000 + i, 1001 + i, 1003 + i, 998 + i, 1));
    expect(TxTimeframe.aggregate(source, 15).bars.length, 20);
    expect(TxTimeframe.aggregate(source, 60).bars.length, 5);
    final four = TxTimeframe.aggregate(source, 240);
    expect(four.bars.length, 2);
    expect(four.bars.first.step, 0);
    expect(four.bars.first.volumeShares, 240);
    expect(four.bars.last.step, 240);
    expect(four.bars.last.volumeShares, 60);
  });

  test('incomplete historical boundary and gaps are disclosed, never padded', () {
    final source = [sample(38,100,101,102,99,2),
        sample(39,101,102,104,101,0),sample(41,102,103,103,100,3)];
    final result = TxTimeframe.aggregate(source, 15);
    expect(result.leftIncomplete, isTrue);
    expect(result.rightIncomplete, isTrue);
    expect(result.hasGaps, isTrue);
    expect(result.bars.length, 1);
    expect(result.bars.first.step, 30);
    expect(result.bars.first.volumeShares, 5);
  });

  test('closed 1m bars stay unchanged and 1d aggregates a full game day', () {
    final source = List.generate(1440, (i) => sample(i,100,100,101,99,0));
    final one = TxTimeframe.aggregate(source, 1);
    expect(identical(one.bars, source), isTrue);
    expect(one.rightIncomplete, isFalse);
    final day = TxTimeframe.aggregate(source, 1440);
    expect(day.bars.single.volumeShares, 0);
    expect(day.rightIncomplete, isFalse);
    expect(day.leftIncomplete, isFalse);
  });

  test('rejects out of order or duplicated committed minutes', () {
    final input = [sample(2,100,100,100,100,0),
        sample(2,100,100,100,100,0)];
    expect(() => TxTimeframe.aggregate(input, 5), throwsStateError);
    expect(() => TxTimeframe.aggregate(input, 0), throwsArgumentError);
  });
}
