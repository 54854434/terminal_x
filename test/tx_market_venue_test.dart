import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';
import '../lib/market/tx_market_venue.dart';

TxMarketVenue cryptoVenue() => TxMarketVenue(
  profile: TxMarketProfile.crypto,
  accounts: {
    'MAKER': TxMarketCore(
      profile: TxMarketProfile.crypto,
      openingCashCents: 1000000,
      initialMarks: {'SIM-BTCUSDT': 100000, 'SIM-ETHUSDT': 30000},
    ),
    'TAKER': TxMarketCore(
      profile: TxMarketProfile.crypto,
      openingCashCents: 1000000,
      initialMarks: {'SIM-BTCUSDT': 100000, 'SIM-ETHUSDT': 30000},
    ),
  },
);

void main() {
  test('independent venue consumes real levels and cancels market remainder', () {
    final venue = cryptoVenue();
    final ask = venue.place(
      id: 'ask-1', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 2,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    expect(ask.status, TxStatus.open);
    expect(venue.depth('SIM-BTCUSDT', TxSide.sell).single.quantity, 2);

    final buy = venue.place(
      id: 'buy-1', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.market, quantity: 3,
      limitPriceCents: null, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    expect(buy.status, TxStatus.cancelled);
    expect(buy.filled, 2);
    expect(venue.fills.single.priceCents, 100000);
    expect(venue.fills.single.makerFeeCents, greaterThan(0));
    expect(venue.fills.single.takerFeeCents, greaterThan(0));
    expect(venue.account('TAKER').position('SIM-BTCUSDT').longQuantity, 2);
    expect(venue.account('MAKER').position('SIM-BTCUSDT').shortQuantity, 2);
    venue.checkInvariants();
  });

  test('price-time levels and FOK are atomic', () {
    final venue = cryptoVenue();
    for (final order in [
      ('ask-a', 1, 100000),
      ('ask-b', 2, 110000),
    ]) {
      venue.place(
        id: order.$1, ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
        side: TxSide.sell, kind: TxKind.limit, quantity: order.$2,
        limitPriceCents: order.$3, timeInForce: TxTimeInForce.gtc,
        gameDay: 1, minuteOfDay: 0);
    }
    final fok = venue.place(
      id: 'fok', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.limit, quantity: 4,
      limitPriceCents: 110000, timeInForce: TxTimeInForce.fok,
      gameDay: 1, minuteOfDay: 0);
    expect(fok.status, TxStatus.rejected);
    expect(venue.fills, isEmpty);
    expect(venue.depth('SIM-BTCUSDT', TxSide.sell)
        .map((level) => level.quantity).toList(), [1, 2]);

    final filled = venue.place(
      id: 'fok-ok', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.limit, quantity: 3,
      limitPriceCents: 110000, timeInForce: TxTimeInForce.fok,
      gameDay: 1, minuteOfDay: 0);
    expect(filled.status, TxStatus.filled);
    expect(venue.fills.map((fill) => fill.priceCents).toList(),
        [100000, 110000]);
  });

  test('post-only, self-trade and reduce-only do not fabricate volume', () {
    final venue = cryptoVenue();
    venue.place(
      id: 'ask', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    final post = venue.place(
      id: 'post', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100001, timeInForce: TxTimeInForce.postOnly,
      gameDay: 1, minuteOfDay: 0);
    expect(post.status, TxStatus.rejected);
    expect(venue.fills, isEmpty);

    final self = TxMarketVenue(
      profile: TxMarketProfile.crypto,
      accounts: {'ONE': TxMarketCore.seeded(profile: TxMarketProfile.crypto)},
    );
    self.place(
      id: 'self-ask', ownerId: 'ONE', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    final selfBuy = self.place(
      id: 'self-buy', ownerId: 'ONE', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.market, quantity: 1,
      limitPriceCents: null, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    expect(selfBuy.status, TxStatus.rejected);
    expect(self.fills, isEmpty);

    final reduce = venue.place(
      id: 'reduce', ownerId: 'TAKER', symbol: 'SIM-ETHUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 30000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0, reduceOnly: true);
    expect(reduce.status, TxStatus.rejected);
    expect(reduce.rejectReason, contains('只减仓'));
  });

  test('venue is isolated from A-share connected core and honors US session', () {
    expect(() => TxMarketVenue(
      profile: TxMarketProfile.aShare,
      accounts: {'A': TxMarketCore.seeded(profile: TxMarketProfile.aShare)},
    ), throwsArgumentError);
    final us = TxMarketVenue(
      profile: TxMarketProfile.usEquity,
      accounts: {
        'US-MAKER': TxMarketCore.seeded(profile: TxMarketProfile.usEquity),
      },
    );
    final closed = us.place(
      id: 'closed', ownerId: 'US-MAKER', symbol: 'SIM-US01',
      side: TxSide.buy, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 10000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 600);
    expect(closed.status, TxStatus.rejected);
    expect(closed.rejectReason, contains('休市'));
  });

  test('venue snapshot round-trips orders and fills with sequence checks', () {
    final venue = cryptoVenue();
    venue.place(
      id: 'resting', ownerId: 'MAKER', symbol: 'SIM-ETHUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 2,
      limitPriceCents: 30000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    venue.place(
      id: 'filled-ask', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    venue.place(
      id: 'filled-buy', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.market, quantity: 1,
      limitPriceCents: null, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    final restored = TxMarketVenue.fromJson(venue.exportJson());
    expect(restored.depth('SIM-ETHUSDT', TxSide.sell).single.quantity, 2);
    expect(restored.order('resting').status, TxStatus.open);
    expect(restored.fills.single.priceCents, 100000);
    restored.checkInvariants();

    final data = Map<String, dynamic>.from(venue.toJson());
    data['schema'] = 3;
    expect(() => TxMarketVenue.fromJsonMap(data), throwsFormatException);

    final invalid = Map<String, dynamic>.from(venue.toJson());
    final orders = List<dynamic>.from(invalid['orders'] as List);
    final first = Map<String, dynamic>.from(orders.first as Map)
      ..['status'] = TxStatus.open.name
      ..['remaining'] = 0;
    orders[0] = first;
    invalid['orders'] = orders;
    expect(() => TxMarketVenue.fromJsonMap(invalid), throwsStateError);

    final missingFillField = Map<String, dynamic>.from(venue.toJson());
    final fills = List<dynamic>.from(missingFillField['fills'] as List);
    final fill = Map<String, dynamic>.from(fills.single as Map)
      ..remove('contractMultiplierUnits');
    fills[0] = fill;
    missingFillField['fills'] = fills;
    expect(() => TxMarketVenue.fromJsonMap(missingFillField), throwsFormatException);
  });

  test('venue broadcasts marks to every account atomically', () {
    final venue = cryptoVenue();
    final before = venue.riskSnapshots;
    final after = venue.markToMarket(
      symbol: 'SIM-BTCUSDT', priceCents: 101000,
    );

    expect(after.keys, containsAll(<String>['MAKER', 'TAKER']));
    expect(venue.account('MAKER').markPriceCents('SIM-BTCUSDT'), 101000);
    expect(venue.account('TAKER').markPriceCents('SIM-BTCUSDT'), 101000);
    expect(before['MAKER']!.cashCents, after['MAKER']!.cashCents);
    expect(() => venue.markToMarket(
      symbol: 'SIM-BTCUSDT', priceCents: 0,
    ), throwsArgumentError);
    expect(venue.account('MAKER').markPriceCents('SIM-BTCUSDT'), 101000);
    venue.checkInvariants();
  });

  test('venue settlement applies funding to both sides at one game-day boundary', () {
    final venue = cryptoVenue();
    venue.place(
      id: 'funding-ask', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    venue.place(
      id: 'funding-buy', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.market, quantity: 1,
      limitPriceCents: null, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);

    final result = venue.settleDay(nextGameDay: 3);
    expect(result.mode, TxMarketMode.crypto);
    expect(result.fromGameDay, 1);
    expect(result.toGameDay, 3);
    expect(result.settlements['TAKER']!.financingPnlCents, -20);
    expect(result.settlements['MAKER']!.financingPnlCents, 20);
    expect(venue.account('TAKER').gameDay, 3);
    expect(venue.account('MAKER').gameDay, 3);
    expect(result.liquidationRequiredAccounts, isEmpty);
    venue.checkInvariants();
  });

  test('execution preview reports real sweep VWAP and leaves venue unchanged', () {
    final venue = cryptoVenue();
    venue.place(
      id: 'preview-ask-a', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    venue.place(
      id: 'preview-ask-b', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 2,
      limitPriceCents: 110000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);

    final beforeOrders = venue.stats.totalOrders;
    final preview = venue.previewOrder(
      ownerId: 'TAKER', symbol: 'SIM-BTCUSDT', side: TxSide.buy,
      kind: TxKind.market, quantity: 3, limitPriceCents: null,
      timeInForce: TxTimeInForce.gtc, gameDay: 1, minuteOfDay: 0);

    expect(preview.accepted, isTrue);
    expect(preview.fullyExecutable, isTrue);
    expect(preview.executableQuantity, 3);
    expect(preview.notionalCents, 320000);
    expect(preview.vwapCents, closeTo(106666.666, .01));
    expect(preview.bestPriceCents, 100000);
    expect(preview.worstPriceCents, 110000);
    expect(preview.levelsConsumed, 2);
    expect(venue.stats.totalOrders, beforeOrders);
    expect(venue.fills, isEmpty);
    expect(venue.depth('SIM-BTCUSDT', TxSide.sell).first.quantity, 1);
  });

  test('venue liquidation consumes only real opposite depth', () {
    final venue = TxMarketVenue(
      profile: TxMarketProfile.crypto,
      accounts: {
        'LIQUIDATED': TxMarketCore(
          profile: TxMarketProfile.crypto,
          openingCashCents: 100000,
          initialMarks: {'SIM-BTCUSDT': 1000000, 'SIM-ETHUSDT': 300000},
        ),
        'BUYER': TxMarketCore(
          profile: TxMarketProfile.crypto,
          openingCashCents: 1000000,
          initialMarks: {'SIM-BTCUSDT': 1000000, 'SIM-ETHUSDT': 300000},
        ),
      },
    );
    venue.account('LIQUIDATED').applyExecution(
      symbol: 'SIM-BTCUSDT', side: TxSide.buy, quantity: 1,
      priceCents: 1000000, gameDay: 1, minuteOfDay: 0);
    venue.markToMarket(symbol: 'SIM-BTCUSDT', priceCents: 900000);
    expect(venue.account('LIQUIDATED').snapshot().liquidationRequired, isTrue);

    final noDepth = venue.liquidateAccountAgainstBook(
        ownerId: 'LIQUIDATED', gameDay: 1, minuteOfDay: 1);
    expect(noDepth.triggered, isTrue);
    expect(noDepth.filledQuantity, 0);
    expect(noDepth.unfilledQuantity, 1);
    expect(noDepth.risk.positions['SIM-BTCUSDT']!.longQuantity, 1);

    venue.place(
      id: 'real-bid', ownerId: 'BUYER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 900000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 1);
    final withDepth = venue.liquidateAccountAgainstBook(
        ownerId: 'LIQUIDATED', gameDay: 1, minuteOfDay: 1,
        orderIdPrefix: 'LIQ-RETRY');
    expect(withDepth.filledQuantity, 1);
    expect(withDepth.unfilledQuantity, 0);
    expect(venue.account('LIQUIDATED').position('SIM-BTCUSDT').isFlat, isTrue);
    venue.checkInvariants();
  });

  test('depth reads are cached until a book mutation', () {
    final venue = cryptoVenue();
    final first = venue.depth('SIM-BTCUSDT', TxSide.sell);
    final second = venue.depth('SIM-BTCUSDT', TxSide.sell);
    expect(first, same(second));
    expect(venue.stats.depthCacheHits, 1);
    venue.place(
      id: 'cache-ask', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    final afterMutation = venue.depth('SIM-BTCUSDT', TxSide.sell);
    expect(afterMutation.single.quantity, 1);
    expect(venue.stats.bookRevision, greaterThan(0));
  });
}
