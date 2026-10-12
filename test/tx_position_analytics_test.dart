import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_position_analytics.dart';

void main() {
  test('average cost and unrealized P/L use actual filled buy prices', () {
    final s = TxSession.fresh();
    final first = s.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 10);
    expect(first.filled, 10);
    final p = TxPositionAnalytics.compute(s)['SIM-A01']!;
    expect(p.quantity, 10);
    expect(p.costBasisCents, 10010);
    expect(p.averagePriceCents, 1001);
    expect(p.realizedPnlCents, 0);
    expect(p.costKnown, isTrue);
    expect(p.unrealizedPnlCents, 0);
  });

  test('partial sale realizes actual net proceeds, leaves average basis', () {
    final s = TxSession.fresh();
    s.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 10);
    final sale = s.placePlayer(symbol: 'SIM-A01', side: TxSide.sell,
        kind: TxKind.market, quantity: 4);
    expect(sale.filled, 4);
    final p = TxPositionAnalytics.compute(s)['SIM-A01']!;
    expect(p.quantity, 6);
    expect(p.costBasisCents, 6006);
    expect(p.realizedPnlCents, 4 * 999 - 4004);
    expect(p.costKnown, isTrue);
  });

  test('resting orders and cancellation do not change cost or holdings', () {
    final s = TxSession.fresh();
    final order = s.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.limit, quantity: 7, limitPriceCents: 500);
    var p = TxPositionAnalytics.compute(s)['SIM-A01']!;
    expect(p.quantity, 0);
    expect(p.costBasisCents, 0);
    s.cancelPlayer(order.id);
    p = TxPositionAnalytics.compute(s)['SIM-A01']!;
    expect(p.costBasisCents, 0);
    expect(p.costKnown, isTrue);
  });

  test('cost basis stays identical after serialized restore', () {
    final s = TxSession.fresh();
    s.placePlayer(symbol: 'SIM-A02', side: TxSide.buy,
        kind: TxKind.market, quantity: 5);
    final before = TxPositionAnalytics.compute(s)['SIM-A02']!;
    final restored = TxSession.importJson(s.exportJson());
    final after = TxPositionAnalytics.compute(restored)['SIM-A02']!;
    expect(after.costBasisCents, before.costBasisCents);
    expect(after.quantity, before.quantity);
    expect(after.realizedPnlCents, before.realizedPnlCents);
  });
}
