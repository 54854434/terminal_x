import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_market_objectives.dart';
import '../lib/widgets/tx_market_objectives_card.dart';

void main() {
  test('strategy objectives and briefing are derived from a real session', () {
    final session = TxSession.freshWithAgents();
    final before = session.exportJson();
    final objectives = TxMarketObjectives.evaluate(session, 'SIM-A01');
    final briefing = TxMarketObjectives.briefing(session, 'SIM-A01');

    expect(objectives.map((item) => item.id), containsAll(<String>[
      'limit-execution', 'book-reading', 'cash-buffer',
    ]));
    expect(objectives.every((item) => item.progress >= 0), isTrue);
    expect(briefing.regime, '上行趋势');
    expect(briefing.spreadCents, greaterThan(0));
    expect(session.exportJson(), before);
  });

  test('limit-execution progress counts only the player real fill', () {
    final session = TxSession.freshWithAgents();
    final ask = session.engine.depth('SIM-A01', TxSide.sell).first;
    final order = session.placePlayer(
      symbol: 'SIM-A01', side: TxSide.buy, kind: TxKind.limit,
      quantity: 2, limitPriceCents: ask.priceCents);
    expect(order.filled, greaterThan(0));
    final task = TxMarketObjectives.evaluate(session, 'SIM-A01')
        .firstWhere((item) => item.id == 'limit-execution');
    expect(task.progress, order.filled);
    expect(task.complete, isFalse);
  });

  test('closed-market research prompt is contextual and does not mutate state',
      () {
    final session = TxSession.freshWithAgents()..step = 120;
    final before = session.exportJson();
    final prompt = TxMarketObjectives.researchPrompt(session, 'SIM-A01');

    expect(prompt.id, contains('breakTime'));
    expect(prompt.options, hasLength(3));
    expect(prompt.correctIndex, inInclusiveRange(0, 2));
    expect(prompt.explanation, isNotEmpty);
    expect(session.exportJson(), before);
  });

  testWidgets('strategy card exposes visible progress and market briefing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TxMarketObjectivesCard(
          session: TxSession.freshWithAgents(),
          symbol: 'SIM-A01',
        ),
      ),
    ));
    expect(find.text('本局策略任务'), findsOneWidget);
    expect(find.text('限价博弈'), findsOneWidget);
    expect(find.textContaining('市场解读'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed strategy card exposes a non-economic research challenge',
      (tester) async {
    final session = TxSession.freshWithAgents()..step = 120;
    final prompt = TxMarketObjectives.researchPrompt(session, 'SIM-A01');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TxMarketObjectivesCard(
          session: session,
          symbol: 'SIM-A01',
        ),
      ),
    ));

    expect(find.text('盘后研究挑战'), findsOneWidget);
    await tester.tap(find.text(
        '${prompt.correctIndex + 1}. ${prompt.options[prompt.correctIndex]}'));
    await tester.pump();
    expect(find.textContaining('回答正确'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
