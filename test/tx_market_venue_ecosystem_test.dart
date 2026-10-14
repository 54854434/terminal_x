import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';
import '../lib/market/tx_market_venue.dart';
import '../lib/market/tx_market_venue_ecosystem.dart';
import '../lib/widgets/tx_market_venue_ecosystem_card.dart';

TxMarketVenue venue() => TxMarketVenue(
      profile: TxMarketProfile.crypto,
      accounts: {
        'MM': TxMarketCore.seeded(profile: TxMarketProfile.crypto),
        'WHALE': TxMarketCore.seeded(profile: TxMarketProfile.crypto),
        'RETAIL': TxMarketCore.seeded(profile: TxMarketProfile.crypto),
      },
    );

void main() {
  test('venue ecosystem is derived from actual cross-account orders', () {
    final market = venue();
    market.place(
      id: 'mm-bid', ownerId: 'MM', symbol: 'SIM-BTCUSDT',
      side: TxSide.buy, kind: TxKind.limit, quantity: 3,
      limitPriceCents: 99900, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    market.place(
      id: 'whale-ask', ownerId: 'WHALE', symbol: 'SIM-BTCUSDT',
      side: TxSide.sell, kind: TxKind.limit, quantity: 2,
      limitPriceCents: 100100, timeInForce: TxTimeInForce.gtc,
      gameDay: 1, minuteOfDay: 0);
    final snapshot = TxMarketVenueEcosystemSnapshot.evaluate(
      venue: market,
      symbol: 'SIM-BTCUSDT',
      actors: {
        'MM': const TxMarketActorProfile(
            id: 'MM', name: '做市商', role: TxMarketActorRole.marketMaker,
            behaviour: '双边报价'),
        'WHALE': const TxMarketActorProfile(
            id: 'WHALE', name: '大户', role: TxMarketActorRole.whale,
            behaviour: '集中仓位'),
      },
    );
    expect(snapshot.bidQuantity, 3);
    expect(snapshot.askQuantity, 2);
    expect(snapshot.spreadCents, 200);
    expect(snapshot.participants.map((item) => item.profile.role),
        containsAll(<TxMarketActorRole>[
          TxMarketActorRole.marketMaker,
          TxMarketActorRole.whale,
          TxMarketActorRole.unknown,
        ]));
  });

  testWidgets('venue ecosystem card exposes structure without story tasks',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxMarketVenueEcosystemCard(
          venue: venue(), symbol: 'SIM-BTCUSDT',
          actors: {
            'MM': const TxMarketActorProfile(
                id: 'MM', name: '做市商',
                role: TxMarketActorRole.marketMaker,
                behaviour: '双边报价'),
          },
        ))));
    expect(find.textContaining('虚拟货币博弈结构'), findsOneWidget);
    expect(find.text('任务'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
