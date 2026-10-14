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

  testWidgets('position guides paint as lines without an outlined preview box',
      (tester) async {
    final candles = List.generate(16, (i) => TxCandle(
      step: i,
      openCents: 1000 + i,
      highCents: 1004 + i,
      lowCents: 996 + i,
      closeCents: 1002 + i,
      volumeShares: i + 1,
    ));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      TxCandleChart(
        candles: candles,
        indicativePriceCents: 1022,
        overlays: const [
          TxChartOverlayLine(
            valueCents: 1008,
            label: '成本',
            valueLabel: '¥10.08 · +¥1.00',
            color: Colors.blue,
            dashed: false,
          ),
          TxChartOverlayLine(
            valueCents: 995,
            label: '强平',
            valueLabel: '¥9.95',
            color: Colors.red,
          ),
        ],
      ),
    )));
    expect(find.byType(TxCandleChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
