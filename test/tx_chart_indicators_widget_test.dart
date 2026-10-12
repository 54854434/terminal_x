import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/widgets/tx_candle_chart.dart';

void main() {
  testWidgets('MA overlays and dashed indicative quote toggled safely',
      (tester) async {
    final candles = List.generate(44, (i) => TxCandle(
      step: i,openCents:1000+i,highCents:1003+i,
      lowCents:997+i,closeCents:1000+i,volumeShares:i*3));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child:TxCandleChart(
          candles:candles,indicativePriceCents:1075)))));
    expect(find.textContaining('MA5 / MA10 / MA20'), findsOneWidget);
    expect(find.textContaining('指示价'), findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.dragFrom(
        tester.getTopLeft(find.byType(TxCandleChart)) +
        const Offset(96, 128), const Offset(140, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
