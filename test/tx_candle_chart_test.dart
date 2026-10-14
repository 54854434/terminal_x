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

  testWidgets('repeated preview frames stay paint-safe', (tester) async {
    final source = List.generate(48, (i) => TxCandle(
      step: i, openCents: 1000 + i, closeCents: 1001 + i,
      highCents: 1004 + i, lowCents: 997 + i, volumeShares: i + 1));
    Widget chart(double price) => MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: TxCandleChart(
        candles: source, activeMinuteStep: 48,
        indicativeFramePriceCents: price, previewSeconds: 12,
      )),
    ));

    await tester.pumpWidget(chart(1040));
    await tester.pumpWidget(chart(980));
    await tester.pumpWidget(chart(1055));
    expect(tester.takeException(), isNull);
  });

  testWidgets('committed bars extend without rebuilding a jumping axis',
      (tester) async {
    final source = List.generate(32, (i) => TxCandle(
      step: i, openCents: 1000 + i, closeCents: 1001 + i,
      highCents: 1004 + i, lowCents: 997 + i, volumeShares: i + 1));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: TxCandleChart(candles: source, activeMinuteStep: 31),
    )));
    for (var i = 32; i < 48; i++) {
      source.add(TxCandle(
        step: i, openCents: 1000 + i, closeCents: 1001 + i,
        highCents: 1004 + i, lowCents: 997 + i, volumeShares: i + 1));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
