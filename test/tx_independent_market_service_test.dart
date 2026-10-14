import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_independent_market_service.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/storage/tx_sqlite_store.dart';

void main() {
  test('crypto board opens with real book, fills and trade-only candles',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);

      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.buy), isNotEmpty);
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.sell), isNotEmpty);
      expect(state.runtime.venue.depth('SIM-ETHUSDT', TxSide.sell), isNotEmpty);
      expect(state.runtime.venue.fills, isNotEmpty);
      expect(state.candlesFor('SIM-BTCUSDT'), isNotEmpty);
      expect(state.candlesFor('SIM-BTCUSDT').every(
          (candle) => candle.volumeShares > 0), isTrue);

      final beforeSequence = state.sequence;
      final order = await service.place(
        mode: TxMarketMode.crypto,
        symbol: 'SIM-BTCUSDT',
        side: TxSide.buy,
        kind: TxKind.market,
        quantity: 1,
        limitPriceCents: null,
        timeInForce: TxTimeInForce.gtc,
        gameDay: 1,
        minuteOfDay: 570,
      );
      expect(order.filled, greaterThan(0));
      expect(state.sequence, greaterThan(beforeSequence));
      expect(state.playerRisk.positions['SIM-BTCUSDT']!.longQuantity,
          greaterThan(0));

      final reopened = TxIndependentMarketService(db);
      final restored = await reopened.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);
      expect(restored.sequence, state.sequence);
      expect(restored.runtime.venue.fills.length,
          state.runtime.venue.fills.length);
      expect(restored.candlesFor('SIM-BTCUSDT'), isNotEmpty);
      restored.runtime.venue.checkInvariants();
    } finally {
      await db.close();
    }
  });

  test('closed non-A board keeps orders rejected and does not create prints',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
        mode: TxMarketMode.usEquity, gameDay: 1, minuteOfDay: 570);
      expect(state.sessionStatus.isOpen, isFalse);
      expect(state.runtime.venue.fills, isEmpty);

      final order = await service.place(
        mode: TxMarketMode.usEquity,
        symbol: 'SIM-US01',
        side: TxSide.buy,
        kind: TxKind.limit,
        quantity: 1,
        limitPriceCents: 10000,
        timeInForce: TxTimeInForce.gtc,
        gameDay: 1,
        minuteOfDay: 570,
      );
      expect(order.status, TxStatus.rejected);
      expect(state.runtime.venue.fills, isEmpty);
      expect((await db.readMarketRuntime(TxMarketMode.usEquity)), isNotNull);

      final crypto = await service.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);
      expect(crypto.runtime.venue.fills, isNotEmpty);
      expect(crypto.sequence, greaterThan(0));
      expect((await db.readMarketRuntime(TxMarketMode.usEquity))!.runtime.mode,
          TxMarketMode.usEquity);
      expect((await db.readMarketRuntime(TxMarketMode.crypto))!.runtime.mode,
          TxMarketMode.crypto);
    } finally {
      await db.close();
    }
  });
}
