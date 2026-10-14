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
  test('R44 intraminute NPC execution is deterministic, funded and replayable', () {
    final first = TxSession.freshWithAgents();
    final copy = TxSession.importJson(first.exportJson());
    final opening = first.engine.fillCount;
    for (final second in [15, 30, 45]) {
      first.marketPulse(second);
      copy.marketPulse(second);
      expect(first.exportJson(), copy.exportJson());
      expect(first.marketTimeStep, 1);
      expect(first.lastPulseSecond, second);
      first.engine.checkInvariants();
    }
    expect(first.engine.fillCount, greaterThan(opening));
    final saved = first.exportJson();
    first.marketPulse(30); // idempotent even after reopening at 0 seconds
    expect(first.exportJson(), saved);
    final reopened = TxSession.importJson(saved);
    expect(reopened.marketTimeStep, 1);
    expect(reopened.lastPulseSecond, 45);
    expect(() => reopened.marketPulse(3), throwsArgumentError);
    final corrupt = saved.replaceFirst('"lastPulseSecond":45',
        '"lastPulseSecond":99');
    expect(() => TxSession.importJson(corrupt), throwsFormatException);
    first.nextTick();
    reopened.nextTick();
    expect(first.exportJson(), reopened.exportJson());
    expect(first.marketTimeStep, 1);
    expect(first.lastPulseSecond, 0);
    expect(first.currentMinuteFills, isNotEmpty);
    first.engine.checkInvariants();
  });

  test('R44 pulse-to-minute candle keeps intraminute real fill volume', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    final trading = TxTradingService(db,
        initialSessionFactory: TxSession.freshWithAgents,
        persistentMarketWorker: true);
    try {
      final initial = await trading.open();
      final candles = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      await db.seedCandleIndex(initial, candles);
      var total = 0;
      for (final second in [15, 30, 45]) {
        final before = trading.current;
        final committed = await trading.marketPulse(second);
        expect(committed.revision, before.revision + 1);
        expect(committed.session.marketTimeStep, 1);
        candles.addCommit(before, committed);
        final realDelta = committed.session.engine.fillCount -
            before.session.engine.fillCount;
        expect(realDelta, greaterThanOrEqualTo(0));
        total += realDelta;
        final disk = (await db.readCurrent())!;
        expect(disk.session.exportJson(), committed.session.exportJson());
      }
      final pulseVolume = candles.forSymbol('SIM-A01').last.volumeShares;
      expect(pulseVolume, greaterThan(0));
      final previous = trading.current;
      final ended = await trading.nextTick();
      candles.addCommit(previous, ended);
      expect(ended.session.marketTimeStep, 1);
      expect(candles.forSymbol('SIM-A01').last.step, 1);
      expect(candles.forSymbol('SIM-A01').last.volumeShares,
          greaterThanOrEqualTo(pulseVolume));
      expect(total, greaterThan(0));
      final reread = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      for (final symbol in TxSession.symbols) {
        final live = candles.forSymbol(symbol).last;
        final rebuilt = reread.forSymbol(symbol).last;
        expect(live.step, rebuilt.step);
        expect(live.openCents, rebuilt.openCents);
        expect(live.highCents, rebuilt.highCents);
        expect(live.lowCents, rebuilt.lowCents);
        expect(live.closeCents, rebuilt.closeCents);
        expect(live.volumeShares, rebuilt.volumeShares);
      }
    } finally {
      await trading.close();
    }
  });

  test('R45 pulse order IDs cannot collide with a future minute boundary', () {
    final session = TxSession.freshWithAgents();
    session.marketPulse(15);
    // The old numeric seed made this exact path create NPC-L-79-0-B during
    // the opening pulse and reuse it with different economics at minute 79.
    session.step = 78;
    expect(() => session.nextTick(), returnsNormally);
    expect(session.engine.orders.keys,
        contains('NPC-L-P-1-15-0-B'));
    expect(session.engine.orders.keys,
        contains('NPC-L-T-79-0-B'));
    session.engine.checkInvariants();
  });

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
    final aggressive = active.engine.orders.values.where((o) =>
        o.id.startsWith('NPC-M-')).toList();
    expect(aggressive, isNotEmpty);
    expect(aggressive.every((o) => o.kind == TxKind.limit &&
        o.timeInForce == TxTimeInForce.ioc), isTrue);
    expect(active.engine.activeOrders.where((o) => o.id.startsWith('NPC-M-')),
        isEmpty);
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
