import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_frame_preview.dart';
import '../lib/market/tx_quote_preview.dart';
import '../lib/market/tx_timeframe.dart';
import '../lib/market/tx_continuous_flow_clock.dart';
import '../lib/widgets/tx_candle_chart.dart';

void main() {
  TxCandle c(int step, int price) => TxCandle(step: step,
      openCents: price, highCents: price+3, lowCents: price-2,
      closeCents: price+1, volumeShares: 7);

  test('fractional frame prices are deterministic across 60/120 FPS', () {
    final a=TxFrameQuote.cents(1000, 4, 10.5, 0);
    final b=TxFrameQuote.cents(1000, 4, 10.5, 0);
    expect(a, b);
    expect(a, isPositive);
    expect(TxFrameQuote.cents(1000, 4, 0, 0), 1000.0);
    for (var i=0; i<60; i++) {
      expect((TxFrameQuote.cents(1000, 4, i.toDouble(), 0) -
          TxQuotePreview.cents(1000, 4, i, 0)).abs(), lessThanOrEqualTo(.51));
    }
    expect(() => TxFrameQuote.cents(1000, 1, -1, 0), throwsArgumentError);
    expect(() => TxFrameQuote.cents(1000, 1, double.nan, 0), throwsArgumentError);
    expect(() => TxFrameQuote.cents(1000, 1, 60, 0), throwsArgumentError);
  });

  test('100x frame-rate independence with identical wall-time', () {
    final flow60=TxContinuousFlowClock(speed:100)..resume();
    final flow120=TxContinuousFlowClock(speed:100)..resume();
    for (var frame=0; frame<30; frame++) {
      expect(flow60.advance(const Duration(microseconds:16666))
          .needsMinuteCommit, isFalse);
    }
    for (var frame=0; frame<60; frame++) {
      expect(flow120.advance(const Duration(microseconds:8333))
          .needsMinuteCommit, isFalse);
    }
    expect((flow60.minuteProgress-flow120.minuteProgress).abs(),lessThan(.001));
    flow60.pause();
    flow120.pause();
    expect(flow60.advance(const Duration(hours:5)).fractionOfMinute,
        flow60.minuteProgress);
    expect(flow120.advance(const Duration(hours:5)).fractionOfMinute,
        flow120.minuteProgress);
  });

  test('one-minute preview always uses an uncommitted spare slot', () {
    final old=c(8, 1000);
    final p=TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: old, nextMinuteStep: 9, periodMinutes: 1,
        framePriceCents: 1003.25, previewHighCents: 1005.0,
        previewLowCents: 999.5);
    expect(p.overlaysLastCommitted, false);
    expect(p.groupStep, 9);
    expect(p.openCents, old.closeCents);
    expect(p.closeCents, 1003.25);
    expect(old.volumeShares, 7);
  });

  test('5m bucket rollover uses new cyan slot, not old committed candle', () {
    final source=List.generate(5, (i)=>c(i,1000+i));
    final old=TxTimeframe.aggregate(source,5).bars.last;
    final p=TxFrameCandleProjection.fromLastCommitted(
      lastAggregated:old, nextMinuteStep:5, periodMinutes:5,
      framePriceCents:1006.25, previewHighCents:1007.0,
      previewLowCents:1005.0);
    expect(p.groupStep,5);
    expect(p.overlaysLastCommitted,false);
    expect(p.openCents,old.closeCents);
  });

  test('5m, 15m, 1h, 4h, day ghost stays inside current bucket', () {
    final minutes=List.generate(41, (i)=>c(i,1000+i));
    for (final period in [5,15,60,240,1440]) {
      final aggregated=TxTimeframe.aggregate(minutes,period).bars;
      final old=aggregated.last;
      final p=TxFrameCandleProjection.fromLastCommitted(
          lastAggregated: old, nextMinuteStep:41, periodMinutes:period,
          framePriceCents:1100.25, previewHighCents:1110.0,
          previewLowCents:980.0);
      expect(p.overlaysLastCommitted, period!=1 && 41~/period==40~/period);
      expect(p.groupStep, 41~/period*period);
      expect(p.highCents, greaterThanOrEqualTo(1110));
      expect(p.lowCents, lessThanOrEqualTo(980));
      expect(aggregated.last.closeCents, old.closeCents);
    }
  });

  test('current 5m projection preserves verified bar while cyan closes change', () {
    final committed = c(20, 1010);
    final first = TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: committed, nextMinuteStep: 25, periodMinutes: 5,
        framePriceCents: 1012.25, previewHighCents: 1014.0,
        previewLowCents: 1009.0);
    final next = TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: committed, nextMinuteStep: 25, periodMinutes: 5,
        framePriceCents: 1013.75, previewHighCents: 1014.0,
        previewLowCents: 1009.0);
    expect(first.overlaysLastCommitted, false);
    expect(next.groupStep, 25);
    expect(next.closeCents, greaterThan(first.closeCents));
    expect(committed.closeCents, 1011);
    expect(committed.volumeShares, 7);
  });

  test('same 15m bucket overlay preserves committed highs and candle origin', () {
    final base = c(30, 1030);
    final ghost = TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: base, nextMinuteStep: 31, periodMinutes: 15,
        framePriceCents: 1034.125, previewHighCents: 1035.0,
        previewLowCents: 1030.5);
    expect(ghost.overlaysLastCommitted, true);
    expect(ghost.groupStep, 30);
    expect(ghost.openCents, base.openCents);
    expect(ghost.highCents, greaterThanOrEqualTo(base.highCents));
    expect(ghost.lowCents, lessThanOrEqualTo(base.lowCents));
    expect(base.closeCents, 1031);
    expect(base.volumeShares, 7);
  });

  test('invalid float quotes and impossible preview envelopes fail closed', () {
    final committed = c(89, 1000);
    expect(() => TxFrameQuote.cents(1000, 89, double.infinity, 0),
        throwsArgumentError);
    expect(() => TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: committed, nextMinuteStep: 90, periodMinutes: 5,
        framePriceCents: 1010.0, previewHighCents: 1001.0,
        previewLowCents: 1000.0), throwsArgumentError);
    expect(() => TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: committed, nextMinuteStep: 1, periodMinutes: 5,
        framePriceCents: 1010.0, previewHighCents: 1010.0,
        previewLowCents: 1000.0), throwsStateError);
  });

  testWidgets('frame preview survives every timeframe and historical browsing',
      (tester) async {
    final candles=List.generate(90,(i)=>c(i,1000+i));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
        SingleChildScrollView(child:TxCandleChart(
          candles:candles,indicativeFramePriceCents:1097.25)))));
    for (final period in ['5分','15分','1时','4时','1日','1分','分时']) {
      final chip = find.widgetWithText(ChoiceChip, period);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      expect(tester.takeException(),isNull);
    }
    expect(candles.last.volumeShares, 7);
  });
}
