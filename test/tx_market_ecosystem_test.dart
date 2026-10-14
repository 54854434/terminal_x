import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_session.dart';
import '../lib/market/tx_market_ecosystem.dart';
import '../lib/widgets/tx_market_ecosystem_card.dart';
import '../lib/market/tx_market_profiles.dart';

void main() {
  test('ecosystem snapshot is derived from real NPC accounts and book', () {
    final session = TxSession.freshWithAgents();
    final snapshot = TxMarketEcosystemSnapshot.evaluate(session, 'SIM-A01');

    expect(snapshot.hasNpcMarket, isTrue);
    expect(snapshot.participants.map((item) => item.role), contains('做市商'));
    expect(snapshot.participants.map((item) => item.role), contains('游资'));
    expect(snapshot.visibleShares, greaterThan(0));
    expect(snapshot.bookNotionalCents, greaterThan(0));
    expect(snapshot.playerEquityCents, session.totalAssetsCents);
  });

  testWidgets('ecosystem card has no quest or story labels', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxMarketEcosystemCard(session: TxSession.freshWithAgents(),
            symbol: 'SIM-A01'))));

    expect(find.text('A股市场生态 · 真实参与者'), findsOneWidget);
    expect(find.text('进阶挑战'), findsNothing);
    expect(find.text('策略执行'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ecosystem card isolates unconnected market profiles',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxMarketEcosystemCard(session: TxSession.freshWithAgents(),
            symbol: 'SIM-A01', profile: TxMarketProfile.crypto))));

    expect(find.text('虚拟货币 · 独立核心'), findsOneWidget);
    expect(find.textContaining('不会复用 A 股现货账本'), findsOneWidget);
    expect(find.text('₮'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
