import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';

void main() {
  test('A-share core enforces session and T+1 before allowing a close', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.aShare,
      openingCashCents: 100000,
      initialMarks: {'SIM-A01': 1000, 'SIM-A02': 2500},
    );

    final buy = core.applyExecution(
      symbol: 'SIM-A01', side: TxSide.buy, quantity: 100,
      priceCents: 1000, gameDay: 1, minuteOfDay: 600);
    expect(buy.position.netQuantity, 100);
    expect(buy.position.availableToClose, 0);
    expect(core.cashCents, 0);
    core.advanceGameDay(1);
    expect(core.position('SIM-A01').availableToClose, 0);
    expect(core.preview(
      symbol: 'SIM-A01', side: TxSide.sell, quantity: 1,
      priceCents: 1000, gameDay: 1, minuteOfDay: 600).accepted, isFalse);
    expect(() => core.applyExecution(
      symbol: 'SIM-A01', side: TxSide.buy, quantity: 1,
      priceCents: 1000, gameDay: 1, minuteOfDay: 720), throwsStateError);

    core.advanceGameDay(2);
    expect(core.position('SIM-A01').availableToClose, 100);
    final sell = core.applyExecution(
      symbol: 'SIM-A01', side: TxSide.sell, quantity: 40,
      priceCents: 1100, gameDay: 2, minuteOfDay: 840);
    expect(sell.realizedPnlCents, 4000);
    expect(sell.position.netQuantity, 60);
    expect(core.cashCents, 44000);
  });

  test('US equity margin core supports short and realizes short profit', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.usEquity,
      openingCashCents: 1000000,
      initialMarks: {'SIM-US01': 10000, 'SIM-US02': 25000},
    );
    final opened = core.applyExecution(
      symbol: 'SIM-US01', side: TxSide.sell, quantity: 10,
      priceCents: 10000, gameDay: 1, minuteOfDay: 1320);
    expect(opened.position.shortQuantity, 10);
    expect(opened.risk.usedMarginCents, 50000);
    expect(opened.risk.freeMarginCents, 950000);

    final closed = core.applyExecution(
      symbol: 'SIM-US01', side: TxSide.buy, quantity: 10,
      priceCents: 9000, gameDay: 1, minuteOfDay: 1321,
      reduceOnly: true);
    expect(closed.realizedPnlCents, 10000);
    expect(closed.position.isFlat, isTrue);
    expect(core.cashCents, 1010000);
  });

  test('futures contract multiplier and margin reject underfunded exposure', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.futures,
      openingCashCents: 100000,
      initialMarks: {'SIM-FUT01': 10000, 'SIM-FUT02': 12000},
    );
    final plan = core.preview(
      symbol: 'SIM-FUT01', side: TxSide.buy, quantity: 1,
      priceCents: 10000, gameDay: 1, minuteOfDay: 600);
    expect(plan.accepted, isFalse);
    expect(plan.reason, contains('保证金不足'));
    expect(core.snapshot().hasPositions, isFalse);
  });

  test('crypto mark-to-market exposes liquidation and explicit force close', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.crypto,
      openingCashCents: 100000,
      initialMarks: {'SIM-BTCUSDT': 1000000, 'SIM-ETHUSDT': 300000},
    );
    core.applyExecution(
      symbol: 'SIM-BTCUSDT', side: TxSide.buy, quantity: 1,
      priceCents: 1000000, gameDay: 1, minuteOfDay: 0);
    core.markToMarket(symbol: 'SIM-BTCUSDT', priceCents: 900000);
    final risk = core.snapshot();
    expect(risk.unrealizedPnlCents, -100000);
    expect(risk.liquidationRequired, isTrue);
    final liquidations = core.forceLiquidate();
    expect(liquidations.length, 1);
    expect(core.position('SIM-BTCUSDT').isFlat, isTrue);
    expect(core.snapshot().realizedPnlCents, -100000);
  });

  test('liquidation guide is read-only and follows the selected position', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.crypto,
      openingCashCents: 100000,
      initialMarks: {'SIM-BTCUSDT': 1000000, 'SIM-ETHUSDT': 300000},
    );
    core.applyExecution(
      symbol: 'SIM-BTCUSDT', side: TxSide.buy, quantity: 1,
      priceCents: 1000000, gameDay: 1, minuteOfDay: 0);
    final before = core.snapshot();
    final guide = core.estimatedLiquidationPriceCents('SIM-BTCUSDT');
    expect(guide, isNotNull);
    expect(guide!, lessThan(1000000));
    expect(core.snapshot().cashCents, before.cashCents);
    expect(core.position('SIM-BTCUSDT').netQuantity, 1);
    expect(core.estimatedLiquidationPriceCents('SIM-ETHUSDT'), isNull);
  });

  test('preview is read-only and weighted average stays deterministic', () {
    final core = TxMarketCore.seeded(profile: TxMarketProfile.forex);
    final before = core.snapshot();
    final preview = core.preview(
      symbol: 'SIM-EURUSD', side: TxSide.buy, quantity: 2,
      priceCents: 10800, gameDay: 1, minuteOfDay: 600);
    expect(preview.accepted, isTrue);
    expect(core.snapshot().cashCents, before.cashCents);
    core.applyExecution(
      symbol: 'SIM-EURUSD', side: TxSide.buy, quantity: 1,
      priceCents: 10800, gameDay: 1, minuteOfDay: 600);
    core.applyExecution(
      symbol: 'SIM-EURUSD', side: TxSide.buy, quantity: 1,
      priceCents: 10900, gameDay: 1, minuteOfDay: 601);
    expect(core.position('SIM-EURUSD').averageEntryCents, 10850);
  });

  test('crypto spot instrument does not inherit perpetual short margin rules', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.crypto,
      openingCashCents: 1000000,
      initialMarks: {'SIM-BTCUSDT': 100000, 'SIM-ETHUSDT': 30000},
    );
    final buy = core.applyExecution(
      symbol: 'SIM-ETHUSDT', side: TxSide.buy, quantity: 2,
      priceCents: 30000, gameDay: 1, minuteOfDay: 0);
    expect(buy.risk.usedMarginCents, 0);
    expect(core.cashCents, 940000);
    final short = core.preview(
      symbol: 'SIM-ETHUSDT', side: TxSide.sell, quantity: 3,
      priceCents: 30000, gameDay: 1, minuteOfDay: 0);
    expect(short.accepted, isFalse);
    expect(short.reason, contains('可平仓数量不足'));
  });

  test('explicit settlement charges borrow and releases no hidden intraday cost', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.usEquity,
      openingCashCents: 1000000,
      initialMarks: {'SIM-US01': 10000, 'SIM-US02': 25000},
    );
    core.applyExecution(
      symbol: 'SIM-US01', side: TxSide.sell, quantity: 10,
      priceCents: 10000, gameDay: 1, minuteOfDay: 1320);
    final before = core.cashCents;
    final settlement = core.settleDay(nextGameDay: 3);
    expect(before, 1000000);
    expect(settlement.days, 2);
    expect(settlement.markToMarketPnlCents, 0);
    expect(settlement.financingPnlCents, -40);
    expect(core.cashCents, 999960);
    expect(core.gameDay, 3);
  });

  test('selected leverage scales margin and persists in the account snapshot', () {
    final core = TxMarketCore.seeded(
      profile: TxMarketProfile.usEquity,
      leverageMultiple: 1,
    );
    expect(core.riskRule('SIM-US01').initialMarginBps, 10000);
    core.setLeverageMultiple(2);
    expect(core.riskRule('SIM-US01').initialMarginBps, 5000);
    final restored = TxMarketCore.fromJson(core.exportJson());
    expect(restored.leverageMultiple, 2);
    expect(restored.maxLeverageMultiple, 2);
  });

  test('isolated margin allocates collateral and releases it on close', () {
    final core = TxMarketCore.seeded(
      profile: TxMarketProfile.crypto,
      openingCashCents: 1000000,
      marginMode: TxMarginMode.isolated,
    );
    final opened = core.applyExecution(
      symbol: 'SIM-BTCUSDT', side: TxSide.buy, quantity: 1,
      priceCents: 5000000, gameDay: 1, minuteOfDay: 0);
    expect(opened.risk.marginMode, TxMarginMode.isolated);
    expect(opened.position.isolatedMarginCents, 250000);
    expect(opened.risk.cashCents, 750000);
    expect(opened.risk.freeMarginCents, 750000);
    expect(opened.risk.equityCents, 1000000);

    core.markToMarket(symbol: 'SIM-BTCUSDT', priceCents: 4900000);
    final healthy = core.snapshot();
    expect(healthy.liquidationRequired, isFalse);
    expect(healthy.liquidationBufferCents, greaterThan(0));
    expect(core.estimatedLiquidationPriceCents('SIM-BTCUSDT'), isNotNull);

    final closed = core.applyExecution(
      symbol: 'SIM-BTCUSDT', side: TxSide.sell, quantity: 1,
      priceCents: 4900000, gameDay: 1, minuteOfDay: 1,
      reduceOnly: true);
    expect(closed.position.isFlat, isTrue);
    expect(closed.position.isolatedMarginCents, 0);
    expect(core.cashCents, 900000);
    expect(core.snapshot().isolatedMarginCents, 0);
  });

  test('margin mode is persisted and cannot change while exposed', () {
    final core = TxMarketCore.seeded(
      profile: TxMarketProfile.futures,
      marginMode: TxMarginMode.isolated,
    );
    final restored = TxMarketCore.fromJson(core.exportJson());
    expect(restored.marginMode, TxMarginMode.isolated);
    core.applyExecution(
      symbol: 'SIM-FUT01', side: TxSide.buy, quantity: 1,
      priceCents: 30000, gameDay: 1, minuteOfDay: 600);
    expect(() => core.setMarginMode(TxMarginMode.cross), throwsStateError);
  });

  test('legacy schema without margin mode restores as cross margin', () {
    final core = TxMarketCore.seeded(profile: TxMarketProfile.crypto);
    final legacy = Map<String, dynamic>.from(core.toJson())
      ..['schema'] = 1
      ..remove('marginMode');
    final positions = (legacy['positions'] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map)
          ..remove('isolatedMarginCents'))
        .toList();
    legacy['positions'] = positions;
    final restored = TxMarketCore.fromJsonMap(legacy);
    expect(restored.marginMode, TxMarginMode.cross);
  });

  test('leveraged US long charges financing only on the borrowed portion', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.usEquity,
      openingCashCents: 1000000,
      initialMarks: {'SIM-US01': 10000, 'SIM-US02': 25000},
      leverageMultiple: 2,
    );
    core.applyExecution(
      symbol: 'SIM-US01', side: TxSide.buy, quantity: 10,
      priceCents: 10000, gameDay: 1, minuteOfDay: 1320);
    final settlement = core.settleDay(nextGameDay: 3);
    expect(settlement.financingPnlCents, -20);
    expect(core.cashCents, 999980);
  });

  test('leverage cannot change while the account is exposed', () {
    final core = TxMarketCore.seeded(profile: TxMarketProfile.futures);
    core.applyExecution(
      symbol: 'SIM-FUT01', side: TxSide.buy, quantity: 1,
      priceCents: 30000, gameDay: 1, minuteOfDay: 600);
    expect(() => core.setLeverageMultiple(1), throwsStateError);
  });

  test('futures settlement realizes mark-to-market at the current mark', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.futures,
      openingCashCents: 1000000,
      initialMarks: {'SIM-FUT01': 10000, 'SIM-FUT02': 12000},
    );
    core.applyExecution(
      symbol: 'SIM-FUT01', side: TxSide.buy, quantity: 1,
      priceCents: 10000, gameDay: 1, minuteOfDay: 600);
    core.markToMarket(symbol: 'SIM-FUT01', priceCents: 10500);
    final settlement = core.settleDay(nextGameDay: 2);
    expect(settlement.markToMarketPnlCents, 150000);
    expect(settlement.financingPnlCents, 0);
    expect(core.position('SIM-FUT01').averageEntryCents, 10500);
    expect(core.snapshot().unrealizedPnlCents, 0);
    expect(core.snapshot().realizedPnlCents, 150000);
  });

  test('execution fee is charged inside the same risk preflight', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.usEquity,
      openingCashCents: 100000,
      initialMarks: {'SIM-US01': 10000, 'SIM-US02': 25000},
    );
    final preview = core.preview(
      symbol: 'SIM-US01', side: TxSide.buy, quantity: 1,
      priceCents: 10000, feeCents: 12, gameDay: 1, minuteOfDay: 1320);
    expect(preview.accepted, isTrue);
    expect(preview.feeCents, 12);
    expect(core.cashCents, 100000);
    final result = core.applyExecution(
      symbol: 'SIM-US01', side: TxSide.buy, quantity: 1,
      priceCents: 10000, feeCents: 12, gameDay: 1, minuteOfDay: 1320);
    expect(result.feeCents, 12);
    expect(core.cashCents, 99988);
  });

  test('all five rules are explicit and independent from A-share ledger', () {
    expect(TxMarketRiskRules.values.length, 5);
    expect(TxMarketRiskRules.aShare.tPlusOne, isTrue);
    expect(TxMarketRiskRules.usEquity.supportsShort, isTrue);
    expect(TxMarketRiskRules.futures.contractMultiplier, 300);
    expect(TxMarketRiskRules.crypto.initialMarginBps, 500);
    expect(TxMarketRiskRules.forex.contractMultiplier, 100000);
    for (final profile in TxMarketProfile.values) {
      final core = TxMarketCore.seeded(profile: profile);
      expect(core.positions, isEmpty);
      expect(core.snapshot().realizedPnlCents, 0);
    }
  });

  test('core snapshot round-trips marks, positions and rejects tampering', () {
    final core = TxMarketCore(
      profile: TxMarketProfile.usEquity,
      openingCashCents: 1000000,
      initialMarks: {'SIM-US01': 10000, 'SIM-US02': 25000},
    );
    core.applyExecution(
      symbol: 'SIM-US01', side: TxSide.sell, quantity: 3,
      priceCents: 10000, gameDay: 1, minuteOfDay: 1320);
    core.markToMarket(symbol: 'SIM-US01', priceCents: 9500);
    final restored = TxMarketCore.fromJson(core.exportJson());
    expect(restored.snapshot().equityCents, core.snapshot().equityCents);
    expect(restored.position('SIM-US01').netQuantity, -3);
    expect(restored.markPriceCents('SIM-US01'), 9500);
    final data = Map<String, dynamic>.from(core.toJson());
    data['schema'] = 99;
    expect(() => TxMarketCore.fromJsonMap(data), throwsFormatException);
  });
}
