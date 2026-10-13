import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/widgets/tx_ticket_submit_bar.dart';

void main() {
  Widget app(TxSide side, bool enabled, bool limit, VoidCallback callback) =>
    MaterialApp(home: Scaffold(body: Column(children: [
      const Spacer(),
      TxTicketSubmitBar(side: side, enabled: enabled,
          isLimit: limit, onReview: callback),
    ])));

  testWidgets('buy review affordance is visible, 48px and calls review once',
      (tester) async {
    var reviews = 0;
    await tester.pumpWidget(app(TxSide.buy, true, false, () => reviews++));
    expect(find.text('检查并买入'), findsOneWidget);
    expect(find.text('模拟交易 · 点击后仍需核对确认'), findsOneWidget);
    expect(find.text('市价'), findsOneWidget);
    expect(tester.getSize(find.byType(FilledButton)).height, 48);
    await tester.tap(find.text('检查并买入'));
    expect(reviews, 1);
  });

  testWidgets('sell review is clearly labeled and limit kind visible',
      (tester) async {
    var reviews = 0;
    await tester.pumpWidget(app(TxSide.sell, true, true, () => reviews++));
    expect(find.text('检查并卖出'), findsOneWidget);
    expect(find.text('限价'), findsOneWidget);
    await tester.tap(find.text('检查并卖出'));
    expect(reviews, 1);
  });

  testWidgets('busy or fault state prevents review entirely', (tester) async {
    var reviews = 0;
    await tester.pumpWidget(app(TxSide.buy, false, true, () => reviews++));
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
    expect(reviews, 0);
  });
}
