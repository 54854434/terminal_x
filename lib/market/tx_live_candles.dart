import 'dart:math' as math;
import 'dart:collection';

import '../engine/tx_session.dart';
import '../storage/tx_sqlite_store.dart';
import 'tx_candle_history.dart';

/// Small memory-only cache. SQLite is the source of truth; on restart the
/// cache is reconstructed once from checksummed committed snapshots.
/// No readHistory() call per tick, avoiding repeated O(history * save-size).
class TxLiveCandles {
  TxLiveCandles._(this._values) {
    for (final entry in _values.entries) {
      _views[entry.key] = UnmodifiableListView<TxCandle>(entry.value);
    }
  }

  static const maxCandles = 160;
  final Map<String, List<TxCandle>> _values;
  final Map<String, List<TxCandle>> _views = {}; 

  factory TxLiveCandles.fromVerifiedHistory(List<TxStoredSession> history) {
    final bySymbol = <String, List<TxCandle>>{};
    for (final symbol in TxSession.symbols) {
      final compiled = TxCandleHistory.fromSnapshots(history, symbol);
      bySymbol[symbol] = compiled.skip(
          math.max(0, compiled.length - maxCandles)).toList();
    }
    return TxLiveCandles._(bySymbol);
  }

  /// Stable read-only views avoid allocating new copies on every UI second.
  List<TxCandle> forSymbol(String symbol) =>
      _views[symbol] ?? (throw ArgumentError.value(symbol));

  /// A single successful SQLite commit; never infer or fabricate fills.
  void addCommit(TxStoredSession before, TxStoredSession after) {
    if (after.revision != before.revision + 1) {
      throw StateError('Missing committed SQLite revision');
    }
    final oldStep = before.session.step;
    final step = after.session.step;
    if (step != oldStep && step != oldStep + 1) {
      throw StateError('Game clock skipped minutes');
    }
    for (final symbol in TxSession.symbols) {
      final candles = _values[symbol]!;
      final pair = TxCandleHistory.fromSnapshots([before, after], symbol);
      final incoming = pair.last;
      if (candles.isEmpty) {
        candles.add(incoming);
      } else if (candles.last.step == incoming.step) {
        final last = candles.removeLast();
        candles.add(TxCandle(
          step: incoming.step,
          openCents: last.openCents,
          highCents: math.max(last.highCents, incoming.highCents),
          lowCents: math.min(last.lowCents, incoming.lowCents),
          closeCents: incoming.closeCents,
          volumeShares: last.volumeShares + incoming.volumeShares,
        ));
      } else if (candles.last.step + 1 == incoming.step) {
        candles.add(incoming);
      } else {
        throw StateError('Candle history is not contiguous');
      }
      if (candles.length > maxCandles) candles.removeAt(0);
    }
  }
}
