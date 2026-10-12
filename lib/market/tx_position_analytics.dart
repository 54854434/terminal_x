/// Player cost basis and P/L based on recorded, validated executions only.
/// Uses moving weighted-average cost. Orders that rest or cancel never
/// change inventory cost. All accounting stays in cents (integer rounding).
import '../engine/tx_session.dart';

class TxPosition {
  const TxPosition({
    required this.symbol,
    required this.quantity,
    required this.costBasisCents,
    required this.marketValueCents,
    required this.realizedPnlCents,
    required this.costKnown,
  });
  final String symbol;
  final int quantity;
  final int costBasisCents;
  final int marketValueCents;
  final int realizedPnlCents;
  final bool costKnown;
  double get averagePriceCents => quantity <= 0 ? 0.0 : costBasisCents / quantity;
  int get unrealizedPnlCents => marketValueCents - costBasisCents;
  double get unrealizedPercent => costBasisCents <= 0 ? 0.0 :
      (marketValueCents - costBasisCents) * 100 / costBasisCents;
}

class TxPositionAnalytics {
  const TxPositionAnalytics._();

  static Map<String, TxPosition> compute(TxSession session) {
    final engine = session.engine;
    final positions = <String, TxPosition>{};
    final actual = engine.account(TxSession.playerId);
    for (final symbol in TxSession.symbols) {
      var quantity = 0;
      var basis = 0;
      var realized = 0;
      var valid = true;
      for (final fill in engine.fills) {
        if (fill.symbol != symbol) continue;
        final buyer = engine.order(fill.buyOrderId).ownerId;
        final seller = engine.order(fill.sellOrderId).ownerId;
        if (buyer == TxSession.playerId) {
          quantity += fill.quantity;
          basis += fill.notionalCents;
        } else if (seller == TxSession.playerId) {
          if (fill.quantity > quantity) {
            valid = false; // An opening share balance cannot be inferred.
            continue;
          }
          final removed = fill.quantity == quantity ? basis :
              (basis * fill.quantity + quantity ~/ 2) ~/ quantity;
          quantity -= fill.quantity;
          basis -= removed;
          realized += fill.notionalCents - removed;
        }
      }
      if (quantity != actual.sharesOf(symbol)) valid = false;
      positions[symbol] = TxPosition(
        symbol: symbol, quantity: actual.sharesOf(symbol),
        costBasisCents: basis,
        marketValueCents: actual.sharesOf(symbol) * session.lastPrice(symbol),
        realizedPnlCents: realized,
        costKnown: valid,
      );
    }
    return positions;
  }
}
