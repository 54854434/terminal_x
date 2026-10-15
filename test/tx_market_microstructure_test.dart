import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_market_microstructure.dart';

void main() {
  test('microstructure counts only matched prints and visible depth', () {
    final snapshot = TxMarketMicrostructureSnapshot.fromPrints(
      prints: [
        const TxMarketPrint(
          id: 'F1', symbol: 'SIM-X', priceCents: 1000, quantity: 10,
          aggressor: TxMarketAggressor.buy),
        const TxMarketPrint(
          id: 'F2', symbol: 'SIM-X', priceCents: 1010, quantity: 4,
          aggressor: TxMarketAggressor.sell),
        const TxMarketPrint(
          id: 'F3', symbol: 'SIM-X', priceCents: 1020, quantity: 3,
          aggressor: TxMarketAggressor.unknown),
      ],
      bids: const [TxBookLevel(990, 20, 2)],
      asks: const [TxBookLevel(1010, 30, 3)],
    );

    expect(snapshot.printCount, 3);
    expect(snapshot.totalVolume, 17);
    expect(snapshot.buyVolume, 10);
    expect(snapshot.sellVolume, 4);
    expect(snapshot.unknownVolume, 3);
    expect(snapshot.buyPressure, closeTo(10 / 14, 0.0001));
    expect(snapshot.visibleDepth, 50);
    expect(snapshot.lastTradePriceCents, 1020);
    expect(snapshot.spreadCents, 20);
    expect(snapshot.aggressiveImbalance, 6);
  });

  test('microstructure retains a bounded newest-first display window', () {
    final snapshot = TxMarketMicrostructureSnapshot.fromPrints(
      prints: [
        for (var index = 0; index < 30; index++)
          TxMarketPrint(
            id: 'F$index', symbol: 'SIM-X', priceCents: 1000 + index,
            quantity: 1, aggressor: TxMarketAggressor.buy),
      ],
      bids: const [],
      asks: const [],
      limit: 4,
    );
    expect(snapshot.prints.map((print) => print.id), ['F26', 'F27', 'F28', 'F29']);
    expect(snapshot.totalVolume, 4);
  });
}
