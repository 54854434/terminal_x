import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_market_book_impact.dart';
import '../lib/market/tx_market_ecosystem.dart';

void main() {
  test('impact preview consumes best-first levels without mutating the book', () {
    final levels = <TxBookLevel>[
      const TxBookLevel(1000, 10, 1),
      const TxBookLevel(1010, 20, 2),
      const TxBookLevel(1030, 50, 3),
    ];
    final impact = TxMarketBookImpact.estimate(
        side: TxSide.buy, levels: levels, quantity: 25);
    expect(impact.executableQuantity, 25);
    expect(impact.unfilledQuantity, 0);
    expect(impact.levelsConsumed, 2);
    expect(impact.notionalCents, 10 * 1000 + 15 * 1010);
    expect(impact.vwapCents, 1006.0);
    expect(impact.priceImpactBasisPoints, 100.0);
  });

  test('ecosystem impact uses player funds and inventory against real depth', () {
    final session = TxSession.freshWithAgents();
    final before = session.exportJson();
    final snapshot = TxMarketEcosystemSnapshot.evaluate(session, 'SIM-A01');
    expect(snapshot.playerBuyImpact.requestedQuantity, greaterThan(0));
    expect(snapshot.playerBuyImpact.executableQuantity,
        snapshot.playerBuyImpact.requestedQuantity);
    expect(snapshot.playerSellImpact.requestedQuantity, 0);
    expect(session.exportJson(), before,
        reason: 'impact preview must not submit or reserve an order');
  });

  test('active order cursor exposes live orders without historical scanning', () {
    final engine = TxEngine();
    engine.registerAccount('BUYER', cashCents: 100000);
    engine.registerAccount('SELLER', cashCents: 0, shares: {'S': 3});
    engine.place(id: 'ASK', ownerId: 'SELLER', symbol: 'S', side: TxSide.sell,
        kind: TxKind.limit, quantity: 3, limitPriceCents: 100);
    expect(engine.activeOrders.map((order) => order.id), contains('ASK'));
    expect(engine.orders.length, 1);
  });

  test('impact preview rejects an unordered or malformed depth snapshot', () {
    expect(() => TxMarketBookImpact.estimate(
      side: TxSide.buy,
      levels: const [TxBookLevel(1010, 1, 1), TxBookLevel(1000, 1, 1)],
      quantity: 1,
    ), throwsStateError);
    expect(() => TxMarketBookImpact.estimate(
      side: TxSide.sell,
      levels: const [TxBookLevel(1000, 0, 1)],
      quantity: 1,
    ), throwsStateError);
  });
}
