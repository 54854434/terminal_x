import 'dart:math' as math;
import 'dart:collection';

import '../engine/tx_session.dart';
import '../storage/tx_sqlite_store.dart';
import 'tx_candle_history.dart';

/// A bounded in-memory read-only minute series. Committed SQLite revisions and
/// explicitly marked automatic-playback observations extend it. The latter
/// are display-only until SQLite flushes; reopening still reconstructs only
/// from recently verified snapshots.
class TxLiveCandles {
  TxLiveCandles._(this._values) {
    for (final entry in _values.entries) {
      _views[entry.key] = UnmodifiableListView<TxCandle>(entry.value);
    }
  }

  // Retain a full game day (plus spare bars) while the app stays active.
  // Larger intervals need >160 minutes; do not increase startup snapshot reads.
  static const maxCandles = 1500;
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

  /// Small, non-authoritative read model for fast startup. SQLite binds it
  /// to the exact verified revision and SHA-256; it cannot create trades.
  /// Only a bounded recent window is serialized, independent of old history.
  Map<String, dynamic> toIndexJson({int limit = 96}) => <String, dynamic>{
    'version': 1,
    'candles': <String, dynamic>{
      for (final symbol in TxSession.symbols)
        symbol: _values[symbol]!.skip(
          math.max(0, _values[symbol]!.length - limit)).map((c) => <int>[
            c.step, c.openCents, c.highCents, c.lowCents,
            c.closeCents, c.volumeShares,
          ]).toList(),
    },
  };

  factory TxLiveCandles.fromIndexJson(Map<String, dynamic> data) {
    if (data['version'] != 1 || data.length != 2) {
      throw const FormatException('Unsupported candle read-model version');
    }
    final raw = Map<String, dynamic>.from(data['candles'] as Map);
    if (raw.length != TxSession.symbols.length ||
        raw.keys.any((symbol) => !TxSession.symbols.contains(symbol))) {
      throw const FormatException('Invalid candle read-model symbols');
    }
    final candles = <String, List<TxCandle>>{};
    for (final symbol in TxSession.symbols) {
      final rows = List<dynamic>.from(raw[symbol] as List);
      if (rows.length > maxCandles) {
        throw const FormatException('Candle read-model exceeds memory bound');
      }
      var previous = -1;
      candles[symbol] = <TxCandle>[];
      for (final row in rows) {
        final data = List<dynamic>.from(row as List);
        if (data.length != 6 || data.any((value) => value is! int)) {
          throw const FormatException('Malformed cached candle');
        }
        final step = data[0] as int;
        final open = data[1] as int;
        final high = data[2] as int;
        final low = data[3] as int;
        final close = data[4] as int;
        final volume = data[5] as int;
        if (step < 0 || step <= previous || open < 1 || close < 1 ||
            low < 1 || high < open || high < close ||
            low > open || low > close || volume < 0) {
          throw const FormatException('Invalid cached candle OHLCV');
        }
        previous = step;
        candles[symbol]!.add(TxCandle(
          step: step, openCents: open, highCents: high, lowCents: low,
          closeCents: close, volumeShares: volume,
        ));
      }
    }
    return TxLiveCandles._(candles);
  }

  List<TxCandle> forSymbol(String symbol) =>
      _views[symbol] ?? (throw ArgumentError.value(symbol));

  /// Append/update a real, verified, committed minute. Never extrapolate a
  /// candle from a display-only indicative preview.
  void addCommit(TxStoredSession before, TxStoredSession after) {
    if (after.revision != before.revision + 1) {
      throw StateError('Missing committed SQLite revision');
    }
    addObservation(before.session, after.session);
  }

  /// Extend the in-memory chart from a real simulation candidate.
  /// This deliberately does not change SQLite, revision numbers, or the
  /// indexed candle cache. It lets automatic saves be batched without hiding
  /// real Rust fills from the live chart.
  void addObservation(TxSession before, TxSession after) {
    final oldStep = before.marketTimeStep;
    final step = after.marketTimeStep;
    if (step < oldStep) {
      throw StateError('Game clock moved backwards');
    }
    // The live UI normally adds one minute at a time.  A deferred automatic
    // save is different: SQLite's indexed read model may still be at the
    // last durable minute while the candidate contains many real minutes.
    // Keep the final verified OHLC as a forward gap instead of inventing
    // bars for minutes that were intentionally not snapshotted.  The chart
    // timeframe layer already marks such gaps; this display cache must never
    // turn a valid batch commit into a storage/trading fault.
    final previousFillCount = before.engine.fillCount;
    final nextFillCount = after.engine.fillCount;
    if (nextFillCount < previousFillCount) {
      throw StateError('Verified trade history shrank');
    }
    for (final symbol in TxSession.symbols) {
      // A same-minute unmatched place/cancel may create a SQLite revision
      // but no new print and no changed market mark. Keep the exact existing
      // candle object; avoid reconstructing the cumulative series, scanning
      // fills or forcing a chart rebuild for this account-only transaction.
      // New game minutes NEVER take this shortcut, even with zero volume.
      if (step == oldStep && previousFillCount == nextFillCount &&
          before.lastPrice(symbol) == after.lastPrice(symbol)) {
        continue;
      }
      final candles = _values[symbol]!;
      final pair = TxCandleHistory.fromSnapshots([
        TxStoredSession(session: before, revision: 1, sha256: 'memory'),
        TxStoredSession(session: after, revision: 2, sha256: 'memory'),
      ], symbol);
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
      } else if (candles.last.step < incoming.step) {
        candles.add(incoming);
      } else {
        throw StateError('Candle history moved backwards');
      }
      if (candles.length > maxCandles) candles.removeAt(0);
    }
  }
}
