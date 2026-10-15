import '../engine/tx_engine.dart';

/// Which side initiated a real matched print. This is inferred from the
/// newer incoming order in the price-time venue; it is never a prediction or
/// a hidden source of liquidity.
enum TxMarketAggressor { buy, sell, unknown }

class TxMarketPrint {
  const TxMarketPrint({
    required this.id,
    required this.symbol,
    required this.priceCents,
    required this.quantity,
    required this.aggressor,
    this.aggressorLabel,
    this.timeLabel,
  });

  final String id;
  final String symbol;
  final int priceCents;
  final int quantity;
  final TxMarketAggressor aggressor;
  final String? aggressorLabel;
  final String? timeLabel;
}

/// Bounded read-only market microstructure summary shared by the connected
/// A-share engine and all independent venues. The caller supplies only real
/// prints and resting levels; this class never mutates a book or account.
class TxMarketMicrostructureSnapshot {
  const TxMarketMicrostructureSnapshot._({
    required this.prints,
    required this.bids,
    required this.asks,
  });

  factory TxMarketMicrostructureSnapshot.fromPrints({
    required Iterable<TxMarketPrint> prints,
    required List<TxBookLevel> bids,
    required List<TxBookLevel> asks,
    int limit = 24,
  }) {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final source = prints.toList(growable: false);
    final start = source.length > limit ? source.length - limit : 0;
    return TxMarketMicrostructureSnapshot._(
      prints: List.unmodifiable(source.skip(start)),
      bids: List.unmodifiable(bids),
      asks: List.unmodifiable(asks),
    );
  }

  final List<TxMarketPrint> prints;
  final List<TxBookLevel> bids;
  final List<TxBookLevel> asks;

  int get printCount => prints.length;
  int get totalVolume => prints.fold(0, (sum, print) => sum + print.quantity);
  int get buyVolume => prints
      .where((print) => print.aggressor == TxMarketAggressor.buy)
      .fold(0, (sum, print) => sum + print.quantity);
  int get sellVolume => prints
      .where((print) => print.aggressor == TxMarketAggressor.sell)
      .fold(0, (sum, print) => sum + print.quantity);
  int get unknownVolume => prints
      .where((print) => print.aggressor == TxMarketAggressor.unknown)
      .fold(0, (sum, print) => sum + print.quantity);

  int get visibleBidVolume =>
      bids.fold(0, (sum, level) => sum + level.quantity);
  int get visibleAskVolume =>
      asks.fold(0, (sum, level) => sum + level.quantity);
  int get visibleDepth => visibleBidVolume + visibleAskVolume;

  double? get buyPressure {
    final known = buyVolume + sellVolume;
    return known == 0 ? null : buyVolume / known;
  }

  int? get lastTradePriceCents => prints.isEmpty ? null : prints.last.priceCents;
  int? get bestBidCents => bids.isEmpty ? null : bids.first.priceCents;
  int? get bestAskCents => asks.isEmpty ? null : asks.first.priceCents;
  int? get spreadCents => bestBidCents == null || bestAskCents == null
      ? null : bestAskCents! - bestBidCents!;
  int get aggressiveImbalance => buyVolume - sellVolume;
}
