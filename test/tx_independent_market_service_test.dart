import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_independent_market_service.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';
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
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.buy, levels: 10),
          hasLength(10));
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.sell, levels: 10),
          hasLength(10));
      expect(state.runtime.venue.depth('SIM-ETHUSDT', TxSide.sell), isNotEmpty);
      expect(state.runtime.venue.fills, isNotEmpty);
      expect(state.candlesFor('SIM-BTCUSDT'), isNotEmpty);
      expect(state.candlesFor('SIM-BTCUSDT').every(
          (candle) => candle.volumeShares > 0), isTrue);
      expect(state.candlesFor('SIM-ETHUSDT'), isNotEmpty);
      expect(state.candlesFor('SIM-ETHUSDT').every(
          (candle) => candle.volumeShares > 0), isTrue);
      final fillsAtOpen = state.runtime.venue.fills.length;
      expect(fillsAtOpen, greaterThanOrEqualTo(12),
          reason: 'FLOW plus finite smart agents should create auditable prints');
      expect(state.runtime.venue.accounts.keys, contains('SMART-TREND'));

      final leverage = await service.setPlayerLeverage(
          mode: TxMarketMode.crypto, multiple: 5);
      expect(leverage, 5);
      expect(state.player.leverageMultiple, 5);
      final marginMode = await service.setPlayerMarginMode(
          mode: TxMarketMode.crypto, marginMode: TxMarginMode.isolated);
      expect(marginMode, TxMarginMode.isolated);
      expect(state.player.marginMode, TxMarginMode.isolated);

      await service.sync(mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 571);
      expect(state.runtime.venue.fills.length, greaterThan(fillsAtOpen));
      expect(state.candlesFor('SIM-BTCUSDT').last.volumeShares, greaterThan(0));
      expect(state.candlesFor('SIM-ETHUSDT').last.volumeShares, greaterThan(0));

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
        minuteOfDay: 571,
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
      expect(restored.player.marginMode, TxMarginMode.isolated);
      expect(restored.candlesFor('SIM-BTCUSDT'), isNotEmpty);
      restored.runtime.venue.checkInvariants();
    } finally {
      await db.close();
    }
  });

  test('background traders add real size while a small order stays inside BBO',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);
      const symbol = 'SIM-BTCUSDT';
      final bids = state.runtime.venue.depth(symbol, TxSide.buy, levels: 10);
      final asks = state.runtime.venue.depth(symbol, TxSide.sell, levels: 10);
      final mark = state.markPriceCents(symbol);
      final spreadBps = (asks.first.priceCents - bids.first.priceCents) *
          10000 / mark;
      expect(spreadBps, lessThan(10.0),
          reason: '独立市场最优价差不应让一手订单看起来像跳价');

      final preview = service.preview(
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
      expect(preview.fullyExecutable, isTrue);
      expect(preview.levelsConsumed, 1);
      expect(preview.bestPriceCents, isNotNull);
      final oneUnitImpactBps =
          (preview.bestPriceCents! - mark).abs() * 10000 / mark;
      expect(oneUnitImpactBps, lessThan(6.0));

      await service.sync(mode: TxMarketMode.crypto,
          gameDay: 1, minuteOfDay: 571);
      final minuteVolume = state.runtime.venue.fills
          .where((fill) => fill.symbol == symbol &&
              fill.gameDay == 1 && fill.minuteOfDay == 571)
          .fold<int>(0, (sum, fill) => sum + fill.quantity);
      expect(minuteVolume, greaterThanOrEqualTo(8),
          reason: 'AI/FLOW 应提供有意义的真实基准成交量');
      expect(state.runtime.venue.fills.any((fill) =>
          fill.symbol == symbol && fill.minuteOfDay == 571 &&
          fill.quantity > 1), isTrue);
    } finally {
      await db.close();
    }
  });

  test('independent marks move and finite pressure creates non-flat OHLC',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final fixtures = <TxMarketMode, int>{
        TxMarketMode.usEquity: 1290,
        TxMarketMode.futures: 570,
        TxMarketMode.crypto: 570,
        TxMarketMode.forex: 570,
      };
      for (final entry in fixtures.entries) {
        final service = TxIndependentMarketService(db);
        final state = await service.open(
            mode: entry.key, gameDay: 1, minuteOfDay: entry.value);
        final symbol = state.profile.instruments.first.symbol;
        final initialMark = state.markPriceCents(symbol);
        for (var minute = entry.value + 1;
            minute <= entry.value + 6;
            minute++) {
          await service.sync(
              mode: entry.key, gameDay: 1, minuteOfDay: minute);
        }
        expect(state.markPriceCents(symbol), isNot(initialMark),
            reason: '${entry.key.name} 标记价应随分钟变化');
        expect(state.candlesFor(symbol).any(
            (candle) => candle.highCents > candle.lowCents), isTrue,
            reason: '${entry.key.name} 背景压力应形成真实高低价');
      }
    } finally {
      await db.close();
    }
  });

  test('every open independent venue emits per-instrument prints and volume',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final openClocks = <TxMarketMode, int>{
        TxMarketMode.usEquity: 1290,
        TxMarketMode.futures: 570,
        TxMarketMode.crypto: 570,
        TxMarketMode.forex: 570,
      };
      for (final entry in openClocks.entries) {
        final state = await service.open(
          mode: entry.key, gameDay: 1, minuteOfDay: entry.value);
        expect(state.sessionStatus.isOpen, isTrue,
            reason: '${entry.key.name} should be open in the fixture');
        expect(state.runtime.venue.fills.length, greaterThanOrEqualTo(4),
            reason: '${entry.key.name} needs both instruments to print');
        final firstSymbol = switch (entry.key) {
          TxMarketMode.usEquity => 'SIM-US01',
          TxMarketMode.futures => 'SIM-FUT01',
          TxMarketMode.crypto => 'SIM-BTCUSDT',
          TxMarketMode.forex => 'SIM-EURUSD',
          TxMarketMode.aShare => throw StateError('unexpected A-share'),
        };
        expect(state.runtime.venue.depth(firstSymbol, TxSide.buy, levels: 10),
            hasLength(10));
        for (final instrument in state.profile.instruments) {
          final candles = state.candlesFor(instrument.symbol);
          expect(candles, isNotEmpty,
              reason: '${entry.key.name}/${instrument.symbol} has no candle');
          expect(candles.last.volumeShares, greaterThan(0),
              reason: '${entry.key.name}/${instrument.symbol} has no volume');
        }
      }
    } finally {
      await db.close();
    }
  });

  test('syncAll keeps opened boards moving while the selected tab changes',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final daytime = await service.syncAll(gameDay: 1, minuteOfDay: 570);
      expect(daytime.keys,
          containsAll(<TxMarketMode>[
            TxMarketMode.usEquity,
            TxMarketMode.futures,
            TxMarketMode.crypto,
            TxMarketMode.forex,
          ]));
      expect(daytime[TxMarketMode.usEquity]!.runtime.venue.fills, isEmpty,
          reason: '美股日间休市不能凭盘口生成成交');
      expect(daytime[TxMarketMode.futures]!.runtime.venue.fills, isNotEmpty);
      expect(daytime[TxMarketMode.crypto]!.runtime.venue.fills, isNotEmpty);
      expect(daytime[TxMarketMode.forex]!.runtime.venue.fills, isNotEmpty);

      final night = await service.syncAll(gameDay: 1, minuteOfDay: 1290);
      final us = night[TxMarketMode.usEquity]!;
      expect(us.sessionStatus.isOpen, isTrue);
      expect(us.runtime.venue.fills, isNotEmpty,
          reason: '切换到美股开市时应补齐真实成交，而不是从零冻结');
      expect(us.candlesFor('SIM-US01').last.volumeShares, greaterThan(0));
      expect(night[TxMarketMode.crypto]!.candlesFor('SIM-BTCUSDT').length,
          greaterThan(1));
    } finally {
      await db.close();
    }
  });

  test('syncAll can leave missing boards cold until their first view', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      await service.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);

      final states = await service.syncAll(
        gameDay: 1, minuteOfDay: 571, openMissing: false);

      expect(states.keys.toList(), <TxMarketMode>[TxMarketMode.crypto]);
      expect(await db.readMarketRuntime(TxMarketMode.usEquity), isNull);
      expect(await db.readMarketRuntime(TxMarketMode.futures), isNull);
      expect(await db.readMarketRuntime(TxMarketMode.forex), isNull);
    } finally {
      await db.close();
    }
  });

  test('background prewarm creates a bounded first-look candle window',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      expect(await service.prewarmNext(gameDay: 1, minuteOfDay: 570),
          TxMarketMode.usEquity);
      final mode = await service.prewarmNext(gameDay: 1, minuteOfDay: 570);
      expect(mode, TxMarketMode.futures);
      final state = service.state(TxMarketMode.futures)!;
      expect(state.candlesFor('SIM-FUT01'), isNotEmpty);
      expect(state.candlesFor('SIM-FUT01').length,
          lessThanOrEqualTo(TxIndependentMarketService.prewarmCandleCount));
    } finally {
      await db.close();
    }
  });

  test('maker quotes refresh on a bounded cadence without losing ten levels',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);
      final initialRefreshes = state.quoteRefreshCount;
      expect(initialRefreshes, greaterThan(0));
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.buy, levels: 10),
          hasLength(10));
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.sell, levels: 10),
          hasLength(10));

      for (var minute = 571; minute <= 574; minute++) {
        await service.sync(
            mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: minute);
      }
      expect(state.quoteRefreshCount, initialRefreshes,
          reason: '正常深度下不应每分钟撤单重挂');

      await service.sync(
          mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 575);
      expect(state.quoteRefreshCount, greaterThan(initialRefreshes));
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.buy, levels: 10),
          hasLength(10));
      expect(state.runtime.venue.depth('SIM-BTCUSDT', TxSide.sell, levels: 10),
          hasLength(10));
    } finally {
      await db.close();
    }
  });

  test('restoring the same open minute refreshes quotes without duplicate prints',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxIndependentMarketService(db);
      final state = await service.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);
      final fillsBeforeRestore = state.runtime.venue.fills.length;

      final reopened = TxIndependentMarketService(db);
      final restored = await reopened.open(
        mode: TxMarketMode.crypto, gameDay: 1, minuteOfDay: 570);

      expect(restored.runtime.venue.fills.length, fillsBeforeRestore,
          reason: '同一分钟恢复只能重建盘口，不能重复生成成交');
      expect(restored.runtime.venue.depth('SIM-BTCUSDT', TxSide.buy,
          levels: 10), hasLength(10));
      expect(restored.runtime.venue.depth('SIM-BTCUSDT', TxSide.sell,
          levels: 10), hasLength(10));
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

      final beforeFastForward =
          (state.runtime.gameDay - 1) * 1440 + state.runtime.minuteOfDay;
      final fastForwarded = await service.fastForwardClosed(
          mode: TxMarketMode.usEquity);
      final afterFastForward =
          (fastForwarded.runtime.gameDay - 1) * 1440 +
              fastForwarded.runtime.minuteOfDay;
      expect(afterFastForward, greaterThan(beforeFastForward));
      expect(fastForwarded.sessionStatus.isOpen, isFalse);
      expect(fastForwarded.runtime.venue.fills, isEmpty);

      final order = await service.place(
        mode: TxMarketMode.usEquity,
        symbol: 'SIM-US01',
        side: TxSide.buy,
        kind: TxKind.limit,
        quantity: 1,
        limitPriceCents: 10000,
        timeInForce: TxTimeInForce.gtc,
        gameDay: fastForwarded.runtime.gameDay,
        minuteOfDay: fastForwarded.runtime.minuteOfDay,
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
