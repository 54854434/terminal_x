/// Read-only order ticket quantity helpers for offline spot trading.
/// No orders, asset freezes or SQLite operations originate in this module.
import '../engine/tx_engine.dart';

class TxTicketSizing {
  const TxTicketSizing._();

  /// Upper bound at a displayed reference price, NOT an executable quantity
  /// guarantee for a multi-level market sweep. 0 if there is no quote/cash.
  static int maxBuyShares(int availableCashCents, int priceCents) {
    if (availableCashCents <= 0 || priceCents <= 0) return 0;
    final shares = availableCashCents ~/ priceCents;
    return shares > TxEngine.maxQuantity ? TxEngine.maxQuantity : shares;
  }

  static int maxSellShares(int availableShares) {
    if (availableShares <= 0) return 0;
    return availableShares > TxEngine.maxQuantity
        ? TxEngine.maxQuantity : availableShares;
  }

  /// Rounds downward to whole shares. Invalid percent is a programming error.
  static int percentShares(int maximumShares, int percent) {
    if (maximumShares < 0 || percent < 1 || percent > 100) {
      throw ArgumentError('Invalid ticket quantity or percentage');
    }
    final bounded = maximumShares > TxEngine.maxQuantity
        ? TxEngine.maxQuantity : maximumShares;
    return (bounded ~/ 100) * percent + (bounded % 100) * percent ~/ 100;
  }

  static int? indicativeNotionalCents(int quantity, int? referencePriceCents) {
    if (quantity < 1 || quantity > TxEngine.maxQuantity ||
        referencePriceCents == null || referencePriceCents < 1 ||
        referencePriceCents > TxEngine.maxPriceCents) return null;
    return quantity * referencePriceCents;
  }
}


/// Confirmation checks a durable revision and the full order-ticket identity.
/// This only rejects stale drafts; the matching engine still owns all actual
/// preflight, freeze, fill, rollback and account-invariant decisions.
class TxTicketReview {
  const TxTicketReview({
    required this.revision,
    required this.symbol,
    required this.side,
    required this.limited,
    required this.quantityText,
    required this.priceText,
  });

  final int revision;
  final String symbol;
  final TxSide side;
  final bool limited;
  final String quantityText;
  final String priceText;

  bool isStillCurrent({
    required int revision,
    required String symbol,
    required TxSide side,
    required bool limited,
    required String quantityText,
    required String priceText,
  }) =>
      revision == this.revision && symbol == this.symbol &&
      side == this.side && limited == this.limited &&
      quantityText == this.quantityText &&
      (!limited || priceText == this.priceText);
}
