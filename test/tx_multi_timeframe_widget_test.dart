import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/market/tx_candle_history.dart';
import '../lib/widgets/tx_candle_chart.dart';

void main() {
  testWidgets('chart supports 1m, 5m, 15m and intraday time-sharing chart',
      (tester) async {
    final source = List.generate(90, (i) => TxCandle(
      step: i, openCents: 1000+i, closeCents: 1001+i,
      highCents: 1002+i, lowCents: 998+i, volumeShares: i));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: TxCandleChart(
        candles: source, indicativePriceCents: 1097)))));
    expect(find.textContaining('模拟 K 线 · 1分'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '5分'));
    await tester.pump();
    expect(find.textContaining('模拟 K 线 · 5分'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '15分'));
    await tester.pump();
    expect(find.textContaining('模拟 K 线 · 15分'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '分时'));
    await tester.pump();
    expect(find.textContaining('模拟分时'), findsOneWidget);
    await tester.tapAt(tester.getTopLeft(find.byType(TxCandleChart)) +
        const Offset(90, 180));
    await tester.pump();
    expect(find.textContaining('O:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every candle timeframe keeps a moving preview body',
      (tester) async {
    final source = List.generate(24, (i) => TxCandle(
      step: i, openCents: 1000 + i, closeCents: 1001 + i,
      highCents: 1003 + i, lowCents: 998 + i, volumeShares: i + 1));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: TxCandleChart(
        candles: source,
        // The source ends at the last committed step. The preview belongs
        // to the next minute; this catches the old higher-timeframe
        // "single moving dot" rebase at the minute boundary.
        activeMinuteStep: 24,
        indicativeFramePriceCents: 1024.5,
        previewSeconds: 18,
      )),
    )));
    for (final period in ['1分', '5分', '15分', '1时', '4时', '1日']) {
      final chip = find.widgetWithText(ChoiceChip, period);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('实时预览'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
