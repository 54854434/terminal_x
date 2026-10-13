import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_ticket_sizing.dart';
import '../lib/engine/tx_engine.dart';

void main() {
  test('buy budget quantized to whole shares without exceeding balance', () {
    expect(TxTicketSizing.maxBuyShares(1000, 301), 3);
    expect(TxTicketSizing.maxBuyShares(300, 301), 0);
    expect(TxTicketSizing.maxBuyShares(301, 301), 1);
  });
  test('no available quote or balance means no buy sizing', () {
    expect(TxTicketSizing.maxBuyShares(0, 1000), 0);
    expect(TxTicketSizing.maxBuyShares(-10, 1000), 0);
    expect(TxTicketSizing.maxBuyShares(10000, 0), 0);
  });
  test('sell sizing does not include reserved inventory', () {
    expect(TxTicketSizing.maxSellShares(0), 0);
    expect(TxTicketSizing.maxSellShares(-1), 0);
    expect(TxTicketSizing.maxSellShares(89), 89);
  });
  test('percentage chunks round down and preserve 100 percent', () {
    expect(TxTicketSizing.percentShares(7, 25), 1);
    expect(TxTicketSizing.percentShares(7, 50), 3);
    expect(TxTicketSizing.percentShares(7, 75), 5);
    expect(TxTicketSizing.percentShares(7, 100), 7);
    expect(TxTicketSizing.percentShares(0, 100), 0);
  });
  test('percentage computes safely at extreme account limits', () {
    expect(TxTicketSizing.maxBuyShares(TxEngine.maxPriceCents *
        (TxEngine.maxQuantity + 1), TxEngine.maxPriceCents),
        TxEngine.maxQuantity);
    expect(TxTicketSizing.maxSellShares(TxEngine.maxQuantity + 12),
        TxEngine.maxQuantity);
    expect(TxTicketSizing.percentShares(TxEngine.maxQuantity + 200, 100),
        TxEngine.maxQuantity);
  });
  test('invalid percentages are rejected instead of generating orders', () {
    expect(() => TxTicketSizing.percentShares(100, 0), throwsArgumentError);
    expect(() => TxTicketSizing.percentShares(100, 101), throwsArgumentError);
    expect(() => TxTicketSizing.percentShares(-1, 50), throwsArgumentError);
  });
  test('review rejects stale revisions, symbol, side and changed input', () {
    const original = TxTicketReview(revision: 12, symbol: 'SIM-A01',
      side: TxSide.buy, limited: true, quantityText: '10', priceText: '9.50');
    bool match({int rev = 12, String symbol = 'SIM-A01',
        TxSide side = TxSide.buy, bool limit = true,
        String quantity = '10', String price = '9.50'}) =>
      original.isStillCurrent(revision: rev, symbol: symbol,
        side: side, limited: limit, quantityText: quantity,
        priceText: price);
    expect(match(), isTrue);
    expect(match(rev: 13), isFalse);
    expect(match(symbol: 'SIM-A02'), isFalse);
    expect(match(side: TxSide.sell), isFalse);
    expect(match(limit: false), isFalse);
    expect(match(quantity: '100'), isFalse);
    expect(match(price: '9.51'), isFalse);
  });
  test('market review does not depend on an unused limit price field', () {
    const review = TxTicketReview(revision: 3, symbol: 'SIM-A02',
      side: TxSide.sell, limited: false, quantityText: '20', priceText: '1');
    expect(review.isStillCurrent(revision: 3, symbol: 'SIM-A02',
      side: TxSide.sell, limited: false,
      quantityText: '20', priceText: '900'), isTrue);
  });
  test('indicative notional is not an executable sweep estimate', () {
    expect(TxTicketSizing.indicativeNotionalCents(3, 205), 615);
    expect(TxTicketSizing.indicativeNotionalCents(4, null), isNull);
    expect(TxTicketSizing.indicativeNotionalCents(0, 100), isNull);
    expect(TxTicketSizing.indicativeNotionalCents(2, -10), isNull);
    expect(TxTicketSizing.indicativeNotionalCents(TxEngine.maxQuantity + 1,
        100), isNull);
  });
}
