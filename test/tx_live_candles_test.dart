import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_live_candles.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

void main() {
  test('revisions yield real 1-minute candles without re-reading whole history', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trading = TxTradingService(db);
      await trading.open();
      final buffer = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      expect(buffer.forSymbol('SIM-A01').length, 1);
      for (var i = 0; i < 22; i++) {
        final before = trading.current;
        await trading.nextTick();
        buffer.addCommit(before, trading.current);
      }
      final a = buffer.forSymbol('SIM-A01');
      expect(a.length, 23);
      expect(a.last.step, 22);
      expect(a.last.closeCents, trading.current.session.lastPrice('SIM-A01'));
      expect(a.skip(1).every((c) => c.volumeShares == 0), isTrue);
      expect(a.map((e)=>e.closeCents).toSet().length, greaterThan(6));

      final before = trading.current;
      await trading.place(symbol: 'SIM-A01', side: TxSide.buy,
          kind: TxKind.market, quantity: 1);
      buffer.addCommit(before, trading.current);
      final last = buffer.forSymbol('SIM-A01').last;
      expect(last.step, 22);
      expect(last.volumeShares, 1);
      expect(last.highCents, greaterThanOrEqualTo(last.closeCents));
      expect(last.lowCents, lessThanOrEqualTo(last.closeCents));
      final reload = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      expect(reload.forSymbol('SIM-A01').last.closeCents, last.closeCents);
      expect(reload.forSymbol('SIM-A01').last.volumeShares, last.volumeShares);
      expect(trading.current.session.engine.account(TxSession.playerId)
          .sharesOf('SIM-A01'), 1);
    } finally {
      await db.close();
    }
  });

  test('candle cache rejects revision gap and simulated time jumps', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trading = TxTradingService(db);
      final first = await trading.open();
      final cache = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      await trading.nextTick();
      await trading.nextTick();
      expect(() => cache.addCommit(first, trading.current), throwsStateError);
    } finally {
      await db.close();
    }
  });
}
