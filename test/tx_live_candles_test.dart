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

  test('candle cache rejects revision gaps and backwards clock movement', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trading = TxTradingService(db);
      final first = await trading.open();
      final cache = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      await trading.nextTick();
      await trading.nextTick();
      expect(() => cache.addCommit(first, trading.current), throwsStateError);
      expect(() => cache.addObservation(trading.current.session,
          first.session), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('deferred automatic candidates remain visible without a SQLite revision',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    final trading = TxTradingService(db,
        initialSessionFactory: TxSession.freshWithAgents,
        automaticSaveMinutes: 5);
    try {
      final initial = await trading.open();
      final cache = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      final pulse = await trading.marketPulse(15, deferSave: true);
      expect(pulse.pending, isTrue);
      expect(pulse.revision, initial.revision);
      cache.addObservation(initial.session, pulse.session);
      expect(cache.forSymbol('SIM-A01').last.step, 1);
      final minute = await trading.nextTick(deferSave: true);
      cache.addObservation(pulse.session, minute.session);
      expect(cache.forSymbol('SIM-A01').last.step, 1);
      expect((await db.readCurrent())!.revision, initial.revision);
    } finally {
      await trading.close();
    }
  });

  test('batched automatic save updates indexed OHLC across pending minutes',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    final trading = TxTradingService(db, automaticSaveMinutes: 3);
    try {
      final initial = await trading.open();
      final index = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      await db.seedCandleIndex(initial, index);

      await trading.nextTick(deferSave: true);
      await trading.nextTick(deferSave: true);
      final committed = await trading.nextTick(deferSave: true);

      expect(committed.pending, isFalse);
      expect(committed.session.marketTimeStep, 3);
      final restoredIndex = await db.readCandleIndex(committed);
      expect(restoredIndex, isNotNull);
      expect(restoredIndex!.forSymbol('SIM-A01').last.step, 3);
      expect(restoredIndex.forSymbol('SIM-A01').last.closeCents,
          committed.session.lastPrice('SIM-A01'));
    } finally {
      await trading.close();
    }
  });
}
