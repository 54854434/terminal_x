import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_independent_market_service.dart';
import '../lib/market/tx_market_conditional_orders.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';
import '../lib/market/tx_market_runtime.dart';
import '../lib/market/tx_market_venue.dart';
import '../lib/storage/tx_sqlite_store.dart';

TxMarketRuntime conditionalRuntime() => TxMarketRuntime(
      venue: TxMarketVenue(
        profile: TxMarketProfile.crypto,
        accounts: {
          'PLAYER': TxMarketCore.seeded(profile: TxMarketProfile.crypto),
          'MM': TxMarketCore.seeded(
            profile: TxMarketProfile.crypto,
            openingCashCents: 3000000000,
            initialLongPositions: {
              'SIM-BTCUSDT': 100,
              'SIM-ETHUSDT': 100,
            },
          ),
        },
      ),
      gameDay: 1,
      minuteOfDay: 570,
    );

void main() {
  test('protection trigger semantics and JSON round-trip are directional', () {
    final sellStop = TxMarketConditionalOrder(
      id: 'stop-1',
      symbol: 'SIM-BTCUSDT',
      side: TxSide.sell,
      kind: TxMarketConditionalOrderKind.stopLoss,
      triggerPriceCents: 100,
      quantity: 2,
      createdGameDay: 1,
      createdMinuteOfDay: 570,
    );
    expect(sellStop.triggerOperator, '≤');
    expect(sellStop.shouldTrigger(99), isTrue);
    expect(sellStop.shouldTrigger(101), isFalse);

    final buyTake = TxMarketConditionalOrder(
      id: 'take-1',
      symbol: 'SIM-BTCUSDT',
      side: TxSide.buy,
      kind: TxMarketConditionalOrderKind.takeProfit,
      triggerPriceCents: 100,
      quantity: 2,
      createdGameDay: 1,
      createdMinuteOfDay: 570,
    );
    expect(buyTake.triggerOperator, '≤');
    expect(buyTake.shouldTrigger(99), isTrue);
    expect(buyTake.shouldTrigger(101), isFalse);

    final restored = TxMarketConditionalOrder.fromJsonMap(sellStop.toJson());
    expect(restored.id, sellStop.id);
    expect(restored.kind, TxMarketConditionalOrderKind.stopLoss);
    expect(restored.side, TxSide.sell);
    expect(restored.quantity, 2);
  });

  test('runtime accepts a legacy schema without protection orders', () {
    final raw = Map<String, dynamic>.from(conditionalRuntime().toJson())
      ..['schema'] = 1
      ..remove('conditionalOrders');
    final restored = TxMarketRuntime.fromJsonMap(raw);
    expect(restored.conditionalOrders, isEmpty);
    expect(restored.mode, TxMarketMode.crypto);
  });

  test('stored protection order triggers a real reduce-only venue order',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
        mode: TxMarketMode.crypto,
        gameDay: 1,
        minuteOfDay: 570,
      );
      const symbol = 'SIM-BTCUSDT';
      final opened = await service.place(
        mode: TxMarketMode.crypto,
        symbol: symbol,
        side: TxSide.buy,
        kind: TxKind.market,
        quantity: 1,
        limitPriceCents: null,
        timeInForce: TxTimeInForce.gtc,
        gameDay: 1,
        minuteOfDay: 570,
      );
      expect(opened.filled, greaterThan(0));
      final mark = state.markPriceCents(symbol);
      final condition = await service.placeConditional(
        mode: TxMarketMode.crypto,
        symbol: symbol,
        kind: TxMarketConditionalOrderKind.stopLoss,
        triggerPriceCents: TxEngine.maxPriceCents,
        quantity: 1,
        gameDay: 1,
        minuteOfDay: 570,
      );
      expect(condition.side, TxSide.sell);
      expect(condition.shouldTrigger(mark), isTrue);
      expect(state.runtime.conditionalOrders, hasLength(1));

      final reopened = TxIndependentMarketService(db);
      final restored = await reopened.open(
        mode: TxMarketMode.crypto,
        gameDay: 1,
        minuteOfDay: 570,
      );
      expect(restored.runtime.conditionalOrders.single.id, condition.id);

      await reopened.sync(
          mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 571);
      expect(restored.runtime.conditionalOrders, isEmpty);
      expect(restored.runtime.venue.orders.any((order) =>
          order.ownerId == TxIndependentMarketState.playerId &&
          order.reduceOnly), isTrue);
      expect(restored.playerRisk.positions[symbol]!.availableToClose, 0);
      expect(restored.runtime.venue.fills.any((fill) =>
          fill.symbol == symbol &&
          (fill.buyOrderId.startsWith('TRIGGER') ||
              fill.sellOrderId.startsWith('TRIGGER'))), isTrue);
    } finally {
      await db.close();
    }
  });

  test('pending protection order can be cancelled before its trigger',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
          mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);
      const symbol = 'SIM-BTCUSDT';
      await service.place(
        mode: TxMarketMode.crypto,
        symbol: symbol,
        side: TxSide.buy,
        kind: TxKind.market,
        quantity: 1,
        limitPriceCents: null,
        timeInForce: TxTimeInForce.gtc,
        gameDay: 1,
        minuteOfDay: 570,
      );
      final condition = await service.placeConditional(
        mode: TxMarketMode.crypto,
        symbol: symbol,
        kind: TxMarketConditionalOrderKind.takeProfit,
        triggerPriceCents: TxEngine.maxPriceCents,
        quantity: 1,
        gameDay: 1,
        minuteOfDay: 570,
      );
      final cancelled = await service.cancelConditional(
          mode: TxMarketMode.crypto, orderId: condition.id);
      expect(cancelled.id, condition.id);
      expect(state.runtime.conditionalOrders, isEmpty);
    } finally {
      await db.close();
    }
  });
}
