import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';
import '../lib/market/tx_market_runtime.dart';
import '../lib/market/tx_market_venue.dart';

TxMarketRuntime cryptoRuntime() => TxMarketRuntime(
  venue: TxMarketVenue(
    profile: TxMarketProfile.crypto,
    accounts: {
      'MAKER': TxMarketCore.seeded(profile: TxMarketProfile.crypto),
      'TAKER': TxMarketCore.seeded(profile: TxMarketProfile.crypto),
    },
  ),
  gameDay: 1,
  minuteOfDay: 0,
);

void main() {
  test('runtime binds order time, marks and settlement to one clock', () {
    final runtime = cryptoRuntime();
    runtime.place(
      id: 'runtime-ask', ownerId: 'MAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 1,
      limitPriceCents: 100000, timeInForce: TxTimeInForce.gtc);
    final buy = runtime.place(
      id: 'runtime-buy', ownerId: 'TAKER', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.market, quantity: 1,
      limitPriceCents: null, timeInForce: TxTimeInForce.gtc);
    expect(buy.status, TxStatus.filled);

    runtime.markToMarket(symbol: 'SIM-BTCUSDT', priceCents: 101000);
    expect(runtime.markRevision, 1);
    expect(runtime.riskSnapshots['MAKER']!.positions['SIM-BTCUSDT']!.netQuantity,
        -1);
    expect(runtime.riskSnapshots['TAKER']!.positions['SIM-BTCUSDT']!.netQuantity,
        1);

    final advance = runtime.advanceClock(
      nextGameDay: 3, nextMinuteOfDay: 12);
    expect(advance.crossedGameDay, isTrue);
    expect(advance.settlement!.settlements['TAKER']!.financingPnlCents, -20);
    expect(advance.settlement!.settlements['MAKER']!.financingPnlCents, 20);
    expect(runtime.gameDay, 3);
    expect(runtime.minuteOfDay, 12);
    expect(runtime.venue.account('TAKER').gameDay, 3);
  });

  test('runtime rejects backward time and preserves the clock', () {
    final runtime = cryptoRuntime();
    expect(() => runtime.advanceClock(nextGameDay: 1, nextMinuteOfDay: 0),
        returnsNormally);
    expect(() => runtime.advanceClock(nextGameDay: 1, nextMinuteOfDay: -1),
        throwsArgumentError);
    expect(() => runtime.advanceClock(nextGameDay: 0, nextMinuteOfDay: 1),
        throwsArgumentError);
    expect(() => runtime.advanceClock(nextGameDay: 0, nextMinuteOfDay: 0),
        throwsArgumentError);
    expect(runtime.gameDay, 1);
    expect(runtime.minuteOfDay, 0);
  });

  test('runtime snapshot round-trips and rejects mode or schema tampering', () {
    final runtime = cryptoRuntime()..markToMarket(
        symbol: 'SIM-BTCUSDT', priceCents: 100100);
    final restored = TxMarketRuntime.fromJson(runtime.exportJson());
    expect(restored.mode, TxMarketMode.crypto);
    expect(restored.markRevision, 1);
    expect(restored.venue.account('MAKER').markPriceCents('SIM-BTCUSDT'),
        100100);

    final invalidSchema = Map<String, dynamic>.from(runtime.toJson())
      ..['schema'] = 99;
    expect(() => TxMarketRuntime.fromJsonMap(invalidSchema),
        throwsFormatException);

    final invalidMode = Map<String, dynamic>.from(runtime.toJson())
      ..['mode'] = TxMarketMode.forex.name;
    expect(() => TxMarketRuntime.fromJsonMap(invalidMode),
        throwsFormatException);
  });
}
