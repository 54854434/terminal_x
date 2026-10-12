import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_live_candles.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

void main() {
  test('unmatched same-minute order does not regenerate stored candles', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trading = TxTradingService(db);
      await trading.open();
      final candles = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      final a = candles.forSymbol('SIM-A01').last;
      final b = candles.forSymbol('SIM-A02').last;
      final before = trading.current;
      // 1-cent passive bid cannot cross the normal simulated ask; it can
      // change player cash reservations but must not invent any trade volume.
      final order = await trading.place(
        symbol: 'SIM-A01', side: TxSide.buy, kind: TxKind.limit,
        quantity: 1, limitPriceCents: 1);
      expect(order.filled, 0);
      expect(trading.current.session.step, before.session.step);
      candles.addCommit(before, trading.current);
      expect(identical(candles.forSymbol('SIM-A01').last, a), isTrue);
      expect(identical(candles.forSymbol('SIM-A02').last, b), isTrue);
      expect(candles.forSymbol('SIM-A01').last.volumeShares, 0);
    } finally {
      await db.close();
    }
  });

  test('committed new minute still creates an OHLCV candle on no fill', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trading = TxTradingService(db);
      await trading.open();
      final candles = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      final before = trading.current;
      await trading.nextTick();
      candles.addCommit(before, trading.current);
      expect(candles.forSymbol('SIM-A01').length, 2);
      expect(candles.forSymbol('SIM-A01').last.step, 1);
    } finally {
      await db.close();
    }
  });
}
