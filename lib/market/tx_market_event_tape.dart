/// Recorded Fill-only market event stream for an eventual event-driven chart.
///
/// The old engine doesn't store intra-minute timestamps. These observations
/// therefore carry an ordinal, NOT a fabricated game-second. An ordinal must
/// never be displayed as if the trade happened at a particular second.
import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import '../storage/tx_sqlite_store.dart';

class TxTradeObservation {
  const TxTradeObservation({
    required this.minute,
    required this.ordinal,
    required this.fillId,
    required this.symbol,
    required this.priceCents,
    required this.quantity,
  });

  final int minute;
  final int ordinal;
  final String fillId;
  final String symbol;
  final int priceCents;
  final int quantity;
}

class TxMinuteEventTape {
  const TxMinuteEventTape._(this.minute, this.observations);

  final int minute;
  final List<TxTradeObservation> observations;

  /// Construct only from two successively committed, checksummed revisions.
  /// No quote or reference-price update ever becomes a trade observation.
  static TxMinuteEventTape fromCommits(
      TxStoredSession before, TxStoredSession after) {
    if (after.revision != before.revision + 1 ||
        after.session.step < before.session.step ||
        after.session.step > before.session.step + 1) {
      throw StateError('Nonconsecutive committed market states');
    }
    final oldFills = before.session.engine.fills;
    final newFills = after.session.engine.fills;
    if (newFills.length < oldFills.length ||
        (oldFills.isNotEmpty &&
         newFills[oldFills.length - 1].id != oldFills.last.id)) {
      throw StateError('Committed fill history changed');
    }
    final observations = <TxTradeObservation>[];
    for (var i = oldFills.length; i < newFills.length; i++) {
      final TxFill fill = newFills[i];
      if (!TxSession.symbols.contains(fill.symbol)) {
        throw StateError('Unsupported fill symbol');
      }
      observations.add(TxTradeObservation(
        minute: after.session.step,
        ordinal: observations.length,
        fillId: fill.id,
        symbol: fill.symbol,
        priceCents: fill.priceCents,
        quantity: fill.quantity,
      ));
    }
    return TxMinuteEventTape._(
      after.session.step, List<TxTradeObservation>.unmodifiable(observations));
  }
}

/// Pure incremental OHLCV accumulator. It never invents transactions.
/// Opening/closing reference marks are deliberately not part of the tape;
/// the caller must distinguish them explicitly from matched trade prices.
class TxTradeCandleAccumulator {
  int? _open;
  int? _high;
  int? _low;
  int? _close;
  int _volume = 0;

  int? get openCents => _open;
  int? get highCents => _high;
  int? get lowCents => _low;
  int? get closeCents => _close;
  int get volumeShares => _volume;

  void add(TxTradeObservation observation) {
    final price = observation.priceCents;
    if (price < 1 || observation.quantity < 1) {
      throw StateError('Invalid matched trade');
    }
    _open ??= price;
    _high = _high == null || price > _high! ? price : _high;
    _low = _low == null || price < _low! ? price : _low;
    _close = price;
    _volume += observation.quantity;
  }
}
