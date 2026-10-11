import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/market/tx_candle_history.dart';
import '../lib/widgets/tx_candle_chart.dart';

void main() {
  testWidgets('candle chart handles no snapshots', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: TxCandleChart(candles: []))));
    expect(find.text('暂无已保存的模拟行情记录'), findsOneWidget);
  });

  testWidgets('interactive candle chart supports drag and zoom', (tester) async {
    final candles = List.generate(70, (i) => TxCandle(
      step: i, openCents: 1000 + i, highCents: 1002 + i,
      lowCents: 998 + i, closeCents: 1001 + i, volumeShares: i,
    ));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: TxCandleChart(candles: candles)),
    )));
    expect(find.textContaining('步 38–69'), findsOneWidget);
    await tester.dragFrom(
      tester.getTopLeft(find.byType(TxCandleChart)) + const Offset(90, 90),
      const Offset(150, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
