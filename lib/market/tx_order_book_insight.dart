/// Read-only microstructure statistics from the actual resting limit book.
/// Five-depth levels provide only a bounded snapshot, not price prediction,
/// synthetic liquidity, a fill, or a claim about hidden market orders.
import '../engine/tx_engine.dart';

class TxOrderBookInsight {
  const TxOrderBookInsight._({
    required this.bestBidCents,
    required this.bestAskCents,
    required this.bidShares,
    required this.askShares,
    required this.bidOrders,
    required this.askOrders,
  });

  final int? bestBidCents;
  final int? bestAskCents;
  final int bidShares;
  final int askShares;
  final int bidOrders;
  final int askOrders;

  bool get hasBothSides => bestBidCents != null && bestAskCents != null;

  /// Absent when either side has no resting executable liquidity.
  int? get spreadCents => hasBothSides
      ? bestAskCents! - bestBidCents! : null;

  /// Basis points of midpoint: 10,000 bp = 100%.
  double? get spreadBasisPoints => hasBothSides
      ? 20000.0 * spreadCents! / (bestBidCents! + bestAskCents!)
      : null;

  /// A liquidity ratio, NOT a forecast of future traded prices.
  /// null distinguishes an empty book from a precisely balanced book.
  double? get bidShareFraction {
    final total = bidShares + askShares;
    return total == 0 ? null : bidShares / total;
  }

  static TxOrderBookInsight fromLevels({
    required List<TxBookLevel> bids,
    required List<TxBookLevel> asks,
  }) {
    // The matching engine returns bids best-first descending and asks
    // best-first ascending. Reject inconsistent inputs, never silently sort
    // away a broken book or manufacture a quote when one side is missing.
    for (var i = 0; i < bids.length; i++) {
      final level = bids[i];
      if (level.priceCents < 1 || level.quantity < 1 || level.orderCount < 1 ||
          (i > 0 && bids[i - 1].priceCents <= level.priceCents)) {
        throw StateError('Invalid bid depth snapshot');
      }
    }
    for (var i = 0; i < asks.length; i++) {
      final level = asks[i];
      if (level.priceCents < 1 || level.quantity < 1 || level.orderCount < 1 ||
          (i > 0 && asks[i - 1].priceCents >= level.priceCents)) {
        throw StateError('Invalid ask depth snapshot');
      }
    }
    if (bids.isNotEmpty && asks.isNotEmpty &&
        bids.first.priceCents >= asks.first.priceCents) {
      throw StateError('Crossed resting order book');
    }
    var bidShares = 0, askShares = 0, bidOrders = 0, askOrders = 0;
    for (final level in bids) {
      bidShares += level.quantity;
      bidOrders += level.orderCount;
    }
    for (final level in asks) {
      askShares += level.quantity;
      askOrders += level.orderCount;
    }
    return TxOrderBookInsight._(
      bestBidCents: bids.isEmpty ? null : bids.first.priceCents,
      bestAskCents: asks.isEmpty ? null : asks.first.priceCents,
      bidShares: bidShares,
      askShares: askShares,
      bidOrders: bidOrders,
      askOrders: askOrders,
    );
  }
}
