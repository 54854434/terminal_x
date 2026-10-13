/// OHLC/volume derived from real engine snapshots. Durable history uses only
/// committed snapshots; the live UI may pass an explicitly labelled candidate
/// before its SQLite revision is flushed.
///
/// Background participants may match multiple times *inside* one simulated
/// minute, so scanning the real new fill prices is necessary to preserve
/// actual candle high/low. Quotes alone never count as traded volume.
import 'dart:math' as math;

import '../engine/tx_session.dart';
import '../storage/tx_sqlite_store.dart';

class TxCandle {
  const TxCandle({
    required this.step,
    required this.openCents,
    required this.highCents,
    required this.lowCents,
    required this.closeCents,
    required this.volumeShares,
  });

  final int step;
  final int openCents;
  final int highCents;
  final int lowCents;
  final int closeCents;
  final int volumeShares;

  bool get rising => closeCents > openCents;
  bool get falling => closeCents < openCents;
  bool get flat => closeCents == openCents;
}

class TxCandleHistory {
  const TxCandleHistory._();

  /// The first verified snapshot is just a baseline. All subsequent OHLC
  /// extensions require recorded market observations and real engine fills.
  static List<TxCandle> fromSnapshots(
    List<TxStoredSession> snapshots,
    String symbol,
  ) {
    if (!TxSession.symbols.contains(symbol)) {
      throw ArgumentError.value(symbol, 'symbol', 'Unsupported symbol');
    }
    if (snapshots.isEmpty) return const <TxCandle>[];
    final result = <TxCandle>[];
    var lastRevision = 0;
    var lastStep = -1;
    var lastFillCount = 0;
    var first = true;
    for (final stored in snapshots) {
      if (stored.revision <= lastRevision) {
        throw StateError('Snapshot revisions are not strictly increasing');
      }
      final session = stored.session;
      final marketStep = session.marketTimeStep;
      if (marketStep < lastStep) {
        throw StateError('Simulation clock went backwards');
      }
      final price = session.lastPrice(symbol);
      if (price <= 0) throw StateError('Invalid historical price');
      final fillCount = session.engine.fillCount;
      if (!first && fillCount < lastFillCount) {
        throw StateError('Trade history shrank between snapshots');
      }
      var volume = 0;
      var low = price;
      var high = price;
      if (!first) {
        for (var i = lastFillCount; i < fillCount; i++) {
          final fill = session.engine.fillAt(i);
          if (fill.symbol != symbol) continue;
          volume += fill.quantity;
          low = math.min(low, fill.priceCents);
          high = math.max(high, fill.priceCents);
        }
      }
      if (result.isEmpty || marketStep != result.last.step) {
        // A new minute opens at the last observable mark. The first snapshot
        // in a shortened history has no known earlier opening mark.
        final open = result.isEmpty ? price : result.last.closeCents;
        result.add(TxCandle(
          step: marketStep,
          openCents: open,
          highCents: math.max(high, open),
          lowCents: math.min(low, open),
          closeCents: price,
          volumeShares: volume,
        ));
      } else {
        final old = result.removeLast();
        result.add(TxCandle(
          step: old.step,
          openCents: old.openCents,
          highCents: math.max(old.highCents, high),
          lowCents: math.min(old.lowCents, low),
          closeCents: price,
          volumeShares: old.volumeShares + volume,
        ));
      }
      lastRevision = stored.revision;
      lastStep = marketStep;
      lastFillCount = fillCount;
      first = false;
    }
    return result;
  }
}
