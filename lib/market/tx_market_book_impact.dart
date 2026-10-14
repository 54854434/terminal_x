import '../engine/tx_engine.dart';

/// Read-only liquidity consumption derived from the actual resting book.
///
/// This is an impact observation, not an order, fill, price forecast or
/// automatic price move. A future market core may use the same calculation
/// during an order preview, but this class never mutates an engine or account.
class TxMarketBookImpact {
  const TxMarketBookImpact({
    required this.side,
    required this.requestedQuantity,
    required this.executableQuantity,
    required this.notionalCents,
    required this.bestPriceCents,
    required this.worstPriceCents,
    required this.levelsConsumed,
  });

  final TxSide side;
  final int requestedQuantity;
  final int executableQuantity;
  final int notionalCents;
  final int? bestPriceCents;
  final int? worstPriceCents;
  final int levelsConsumed;

  int get unfilledQuantity => requestedQuantity - executableQuantity;
  bool get fullyExecutable => requestedQuantity > 0 && unfilledQuantity == 0;
  double? get vwapCents => executableQuantity == 0
      ? null
      : notionalCents / executableQuantity;

  /// Difference between the best visible price and the last consumed level,
  /// in basis points. A single-level sweep is therefore 0 bp.
  double? get priceImpactBasisPoints {
    if (bestPriceCents == null || worstPriceCents == null ||
        bestPriceCents == 0) return null;
    return (worstPriceCents! - bestPriceCents!).abs() * 10000.0 /
        bestPriceCents!;
  }

  static TxMarketBookImpact estimate({
    required TxSide side,
    required List<TxBookLevel> levels,
    required int quantity,
  }) {
    if (quantity < 0 || quantity > TxEngine.maxQuantity) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    if (levels.isEmpty || quantity == 0) {
      return TxMarketBookImpact(
        side: side,
        requestedQuantity: quantity,
        executableQuantity: 0,
        notionalCents: 0,
        bestPriceCents: null,
        worstPriceCents: null,
        levelsConsumed: 0,
      );
    }

    var remaining = quantity;
    var filled = 0;
    var notional = 0;
    var consumed = 0;
    int? best;
    int? worst;
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      if (level.priceCents < 1 || level.quantity < 1 ||
          level.orderCount < 1) {
        throw StateError('Invalid book impact level');
      }
      if (i > 0) {
        final previous = levels[i - 1].priceCents;
        final ordered = side == TxSide.buy
            ? previous <= level.priceCents // asks: best-first ascending
            : previous >= level.priceCents; // bids: best-first descending
        if (!ordered) throw StateError('Unordered book impact levels');
      }
      if (remaining == 0) break;
      final take = remaining < level.quantity ? remaining : level.quantity;
      best ??= level.priceCents;
      worst = level.priceCents;
      filled += take;
      notional += take * level.priceCents;
      if (notional > TxEngine.maxNotionalCents) {
        throw StateError('Book impact notional exceeds engine limit');
      }
      consumed++;
      remaining -= take;
    }
    return TxMarketBookImpact(
      side: side,
      requestedQuantity: quantity,
      executableQuantity: filled,
      notionalCents: notional,
      bestPriceCents: best,
      worstPriceCents: worst,
      levelsConsumed: consumed,
    );
  }
}
