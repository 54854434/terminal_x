import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';

void main() {
  test('empty player order history is bounded and non-mutating', () {
    final s = TxSession.fresh();
    expect(s.recentPlayerOrders(), isEmpty);
    expect(s.activePlayerOrders, isEmpty);
    expect(() => s.recentPlayerOrders(limit: 0), throwsArgumentError);
  });
  test('bounded recent orders equal the full historical sorted prefix', () {
    final s = TxSession.fresh();
    for (var i = 0; i < 22; i++) {
      s.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
          kind: TxKind.limit, quantity: 1, limitPriceCents: 700 + i);
    }
    final before = s.exportJson();
    for (final limit in [1, 3, 10, 22, 30]) {
      expect(s.recentPlayerOrders(limit: limit).map((e) => e.id).toList(),
        s.playerOrders.take(limit).map((e) => e.id).toList());
    }
    expect(s.exportJson(), before);
  });
  test('cancelled and filled orders never appear as active', () {
    final s = TxSession.fresh();
    final open = s.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.limit,
        quantity: 2, limitPriceCents: 700);
    final other = s.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.limit,
        quantity: 2, limitPriceCents: 701);
    s.cancelPlayer(open.id);
    final actual = s.playerOrders.where((o) =>
      o.status == TxStatus.open || o.status == TxStatus.partiallyFilled)
      .map((o) => o.id).toList();
    expect(s.activePlayerOrders.map((o) => o.id).toList(), actual);
    expect(s.activePlayerOrders.single.id, other.id);
  });
  test('bounded query is identical after JSON save and restore', () {
    final s = TxSession.fresh();
    for (var i = 0; i < 12; i++) {
      s.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
        kind: TxKind.limit, quantity: 1, limitPriceCents: 720 + i);
    }
    final restored = TxSession.importJson(s.exportJson());
    expect(restored.recentPlayerOrders(limit: 5).map((o) => o.id).toList(),
      s.recentPlayerOrders(limit: 5).map((o) => o.id).toList());
    expect(restored.activePlayerOrders.map((o) => o.id).toList(),
      s.activePlayerOrders.map((o) => o.id).toList());
    restored.engine.checkInvariants();
  });
  test('R30 indexed price-time book matches historical reference across mutations', () {
    final e = TxEngine();
    e.registerAccount('BUYER', cashCents: 2000000);
    e.registerAccount('SELLER', cashCents: 2000000,
        shares: <String, int>{'SIM-X': 300});
    e.registerAccount('OTHER', cashCents: 2000000,
        shares: <String, int>{'SIM-Y': 300});
    final first = e.place(id: 'ask-1', ownerId: 'SELLER',
        symbol: 'SIM-X', side: TxSide.sell, kind: TxKind.limit,
        quantity: 4, limitPriceCents: 100);
    final second = e.place(id: 'ask-2', ownerId: 'SELLER',
        symbol: 'SIM-X', side: TxSide.sell, kind: TxKind.limit,
        quantity: 6, limitPriceCents: 100);
    e.place(id: 'ask-y', ownerId: 'OTHER', symbol: 'SIM-Y',
        side: TxSide.sell, kind: TxKind.limit,
        quantity: 8, limitPriceCents: 99);
    e.place(id: 'bid-low', ownerId: 'BUYER', symbol: 'SIM-X',
        side: TxSide.buy, kind: TxKind.limit,
        quantity: 7, limitPriceCents: 95);

    void compareDepth(TxEngine engine) {
      for (final symbol in <String>['SIM-X', 'SIM-Y']) {
        for (final side in TxSide.values) {
          final aggregates = <int, List<int>>{};
          for (final o in engine.orders.values) {
            if (o.symbol != symbol || o.side != side ||
                o.kind != TxKind.limit || !o.timeInForce.canRest ||
                o.remaining == 0 ||
                (o.status != TxStatus.open &&
                 o.status != TxStatus.partiallyFilled)) continue;
            final row = aggregates.putIfAbsent(o.limitPriceCents!,
                () => <int>[0, 0]);
            row[0] += o.remaining;
            row[1] += 1;
          }
          final prices = aggregates.keys.toList()..sort();
          if (side == TxSide.buy) prices.sort((a, b) => b.compareTo(a));
          final levels = engine.depth(symbol, side, levels: 20);
          expect(levels.map((o) => o.priceCents).toList(), prices);
          for (final level in levels) {
            expect(level.quantity, aggregates[level.priceCents]![0]);
            expect(level.orderCount, aggregates[level.priceCents]![1]);
          }
        }
      }
      engine.checkInvariants();
    }

    compareDepth(e);
    final partial = e.place(id: 'market-buy', ownerId: 'BUYER',
        symbol: 'SIM-X', side: TxSide.buy, kind: TxKind.market,
        quantity: 7);
    expect(partial.status, TxStatus.filled);
    expect(first.status, TxStatus.filled);
    expect(second.status, TxStatus.partiallyFilled);
    expect(second.remaining, 3);
    expect(e.fills.map((f) => f.sellOrderId).toList(),
        <String>['ask-1', 'ask-2']);
    compareDepth(e);
    e.cancel('ask-2', ownerId: 'SELLER');
    compareDepth(e);
    final recovered = TxEngine.importJson(e.exportJson());
    expect(recovered.exportJson(), e.exportJson());
    compareDepth(recovered);
    expect(recovered.activeOrders.any((o) => o.id == 'ask-2'), isFalse);
  });

  test('R30 active index does not grow with completed order history', () {
    final e = TxEngine();
    e.registerAccount('SELLER', cashCents: 10000000,
        shares: <String, int>{'X': 600});
    for (var i = 0; i < 120; i++) {
      final id = 'historical-$i';
      e.place(id: id, ownerId: 'SELLER', symbol: 'X',
          side: TxSide.sell, kind: TxKind.limit,
          quantity: 1, limitPriceCents: 200 + i);
      e.cancel(id, ownerId: 'SELLER');
    }
    expect(e.orders.length, 120);
    expect(e.activeOrders, isEmpty);
    expect(e.depth('X', TxSide.sell), isEmpty);
    final fresh = e.place(id: 'remaining', ownerId: 'SELLER',
        symbol: 'X', side: TxSide.sell, kind: TxKind.limit,
        quantity: 2, limitPriceCents: 250);
    expect(e.activeOrders.map((o) => o.id).toList(), <String>['remaining']);
    expect(e.depth('X', TxSide.sell).single.quantity, 2);
    expect(TxEngine.importJson(e.exportJson()).order(fresh.id).remaining, 2);
    e.checkInvariants();
  });

  test('R30 one-minute simulation retains exact old JSON after reload', () {
    final oldSession = TxSession.fresh();
    final before = oldSession.exportJson();
    final imported = TxSession.importJson(before);
    for (var i = 0; i < 3; i++) {
      oldSession.nextTick();
      imported.nextTick();
      expect(imported.exportJson(), oldSession.exportJson());
      expect(imported.engine.activeOrders.every((o) =>
          o.kind == TxKind.limit && o.timeInForce.canRest &&
          o.remaining > 0), isTrue);
    }
    imported.engine.checkInvariants();
  });

}
