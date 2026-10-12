import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_live_candles.dart';
import '../lib/market/tx_npc_market.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

void main() {
  test('different market regimes appear during one 60-minute session', () {
    expect(TxSession.marketRegime(1, 0), 0);
    expect(TxSession.marketRegime(20, 0), 0);
    expect(TxSession.marketRegime(21, 0), 1);
    expect(TxSession.marketRegime(41, 0), 2);
    expect(TxSession.marketRegime(61, 0), 3);
    expect(TxSession.marketRegime(1, 1), 2);
  });

  test('normal fresh/old session stays passive; active preview adds real traders', () {
    final old = TxSession.fresh();
    old.nextTick();
    expect(old.engine.fills, isEmpty);
    expect(TxNpcMarket.isEnabled(old.engine), isFalse);
    final active = TxSession.freshWithAgents();
    expect(TxNpcMarket.isEnabled(active.engine), isTrue);
    expect(active.engine.fills, isEmpty);
    for (final agent in TxNpcMarket.participants) {
      expect(active.engine.account(agent).availableCashCents, greaterThan(0));
      expect(active.engine.account(agent).availableSharesOf('SIM-A01'), greaterThan(0));
    }
    active.nextTick();
    expect(active.currentMinuteFills, isNotEmpty);
    expect(active.currentMinuteFills.any((f) => f.symbol == 'SIM-A01'), isTrue);
    expect(active.currentMinuteFills.any((f) => f.symbol == 'SIM-A02'), isTrue);
    expect(active.playerFills, isEmpty);
    active.engine.checkInvariants();
  });

  test('only funded and matched orders generate trades and OHLC wicks', () {
    final before = TxSession.freshWithAgents();
    final after = TxSession.importJson(before.exportJson())..nextTick();
    final history = TxCandleHistory.fromSnapshots([
      TxStoredSession(session: before, revision: 1, sha256: 'test'),
      TxStoredSession(session: after, revision: 2, sha256: 'test'),
    ], 'SIM-A01');
    final candle = history.last;
    final actual = after.engine.fills.where((f) => f.symbol == 'SIM-A01').toList();
    expect(actual, isNotEmpty);
    expect(candle.step, 1);
    expect(candle.volumeShares,
        actual.fold<int>(0, (sum, f) => sum + f.quantity));
    final prices = [before.lastPrice('SIM-A01'), after.lastPrice('SIM-A01'),
      ...actual.map((f) => f.priceCents)];
    expect(candle.highCents, prices.reduce((a, b) => a > b ? a : b));
    expect(candle.lowCents, prices.reduce((a, b) => a < b ? a : b));
    for (final fill in after.engine.fills) {
      final buy = after.engine.order(fill.buyOrderId);
      final sell = after.engine.order(fill.sellOrderId);
      expect(buy.ownerId, isNot(sell.ownerId));
      final maker = buy.sequence < sell.sequence ? buy : sell;
      expect(maker.kind, TxKind.limit);
      expect(fill.priceCents, maker.limitPriceCents);
    }
  });

  test('background market may consume a competitive PLAYER resting limit', () {
    final session = TxSession.freshWithAgents();
    final player = session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
      kind: TxKind.limit, quantity: 1, limitPriceCents: 1000);
    expect(player.status, TxStatus.open);
    TxNpcMarket.tradeMinute(session.engine, 1, TxSession.symbols,
        [1000, 2500], [-1, -1]);
    expect(session.engine.order(player.id).status, TxStatus.filled);
    expect(session.engine.account(TxSession.playerId).sharesOf('SIM-A01'), 1);
    session.engine.checkInvariants();
  });

  test('minute replay, engine assets and persistent restore are deterministic', () {
    final a = TxSession.freshWithAgents();
    final b = TxSession.freshWithAgents();
    final openingCash = a.engine.accounts.values.fold<int>(
        0, (sum, x) => sum + x.cashCents);
    final openingA = a.engine.accounts.values.fold<int>(
        0, (sum, x) => sum + x.sharesOf('SIM-A01'));
    final openingB = a.engine.accounts.values.fold<int>(
        0, (sum, x) => sum + x.sharesOf('SIM-A02'));
    for (var i = 0; i < 6; i++) {
      a.nextTick();
      b.nextTick();
      expect(a.exportJson(), b.exportJson());
    }
    expect(a.engine.accounts.values.fold<int>(
        0, (sum, x) => sum + x.cashCents), openingCash);
    expect(a.engine.accounts.values.fold<int>(
        0, (sum, x) => sum + x.sharesOf('SIM-A01')), openingA);
    expect(a.engine.accounts.values.fold<int>(
        0, (sum, x) => sum + x.sharesOf('SIM-A02')), openingB);
    a.engine.checkInvariants();
    final restored = TxSession.importJson(a.exportJson());
    expect(TxNpcMarket.isEnabled(restored.engine), isTrue);
    a.nextTick();
    restored.nextTick();
    expect(a.exportJson(), restored.exportJson());
  });

  test('SQLite persistence rebuilds identical background candle with true volume', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trader = TxTradingService(db,
          initialSessionFactory: TxSession.freshWithAgents);
      await trader.open();
      final cache = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      for (var i = 0; i < 4; i++) {
        final before = trader.current;
        await trader.nextTick();
        cache.addCommit(before, trader.current);
      }
      final cached = cache.forSymbol('SIM-A01').last;
      final rebuilt = TxLiveCandles.fromVerifiedHistory(await db.readHistory())
          .forSymbol('SIM-A01').last;
      expect(cached.volumeShares, greaterThan(0));
      expect(cached.volumeShares, rebuilt.volumeShares);
      expect(cached.openCents, rebuilt.openCents);
      expect(cached.highCents, rebuilt.highCents);
      expect(cached.lowCents, rebuilt.lowCents);
      expect(cached.closeCents, rebuilt.closeCents);
      final reopened = TxTradingService(db,
          initialSessionFactory: TxSession.freshWithAgents);
      expect((await reopened.open()).session.step, 4);
      expect(reopened.current.session.engine.fills, isNotEmpty);
    } finally {
      await db.close();
    }
  });
}
