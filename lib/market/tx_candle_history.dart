/// OHLC calculated ONLY from verified committed SQLite session snapshots.
///
/// One candle represents one simulation step. Multiple committed trades in the
/// same step update OHLC and volume; the first observed revision in a truncated
/// history defines the first candle's open. We do not invent market history.
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

  bool get rising => closeCents >= openCents;
}

class TxCandleHistory {
  const TxCandleHistory._();

  /// Revisions MUST be in strictly increasing order; step numbers may repeat.
  /// The first available revision is a baseline for incremental volume.
  static List<TxCandle> fromSnapshots(
    List<TxStoredSession> snapshots,
    String symbol,
  ) {
    if (!TxSession.symbols.contains(symbol)) {
      throw ArgumentError.value(symbol, 'symbol', 'Unsupported symbol');
    }
    if (snapshots.isEmpty) return const <TxCandle>[];
    final results = <TxCandle>[];
    var previousRevision = 0;
    var previousStep = -1;
    var previousFillCount = 0;
    var first = true;
    for (final stored in snapshots) {
      if (stored.revision <= previousRevision) {
        throw StateError('Snapshot revisions are not strictly increasing');
      }
      final session = stored.session;
      if (session.step < previousStep) {
        throw StateError('Simulation clock went backwards');
      }
      final price = session.lastPrice(symbol);
      if (price <= 0) throw StateError('Invalid historical price');
      final fills = session.engine.fills;
      if (!first && fills.length < previousFillCount) {
        throw StateError('Trade history shrank between snapshots');
      }
      var volume = 0;
      if (!first) {
        for (var i = previousFillCount; i < fills.length; i++) {
          if (fills[i].symbol == symbol) volume += fills[i].quantity;
        }
      }
      if (results.isEmpty || session.step != results.last.step) {
        results.add(TxCandle(
          step: session.step,
          openCents: price,
          highCents: price,
          lowCents: price,
          closeCents: price,
          volumeShares: volume,
        ));
      } else {
        final old = results.removeLast();
        results.add(TxCandle(
          step: old.step,
          openCents: old.openCents,
          highCents: old.highCents > price ? old.highCents : price,
          lowCents: old.lowCents < price ? old.lowCents : price,
          closeCents: price,
          volumeShares: old.volumeShares + volume,
        ));
      }
      previousRevision = stored.revision;
      previousStep = session.step;
      previousFillCount = fills.length;
      first = false;
    }
    return results;
  }
}
