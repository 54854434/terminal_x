import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_session.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_frame_preview.dart';
import '../lib/market/tx_quote_preview.dart';
import '../lib/market/tx_timeframe.dart';
import '../lib/market/tx_continuous_flow_clock.dart';
import '../lib/widgets/tx_candle_chart.dart';
import '../lib/widgets/tx_back_exit_guard.dart';

void main() {
  testWidgets('R37 Android Back is intercepted instead of dismissing game',
      (tester) async {
    var backRequests = 0;
    await tester.pumpWidget(MaterialApp(home: TxBackExitGuard(
      onBack: () async { backRequests++; },
      child: const Scaffold(body: Center(child: Text('game stays open'))),
    )));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(backRequests, 1);
    expect(find.text('game stays open'), findsOneWidget);
  });

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

  test('R40 provisional candles use current bucket rise/fall for display', () {
    final last = c(10, 1000);
    TxFrameCandleProjection preview(double value) =>
        TxFrameCandleProjection.fromLastCommitted(
          lastAggregated: last, nextMinuteStep: 11, periodMinutes: 1,
          framePriceCents: value,
          previewHighCents: value > 1001 ? value : 1001,
          previewLowCents: value < 1001 ? value : 1001,
        );
    expect(preview(1020).rising, isTrue);
    expect(preview(980).rising, isFalse);
    expect(last.highCents, 1003);
    expect(last.volumeShares, 7);
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

  test('R32 cyan wick extrema survive successive 1m SQLite saves in 5m bar', () {
    final wick = TxIndicativeWickMemory();
    wick.observe(nextMinuteStep: 21, periodMinutes: 5,
        committedCloseCents: 1000, framePriceCents: 1040);
    expect(wick.groupStep, 20);
    expect(wick.highCents, 1040);
    wick.observe(nextMinuteStep: 21, periodMinutes: 5,
        committedCloseCents: 1000, framePriceCents: 985);
    expect(wick.lowCents, 985);
    // At the next one-minute commit the parent 5m bucket remains unchanged.
    wick.observe(nextMinuteStep: 22, periodMinutes: 5,
        committedCloseCents: 1010, framePriceCents: 1003);
    expect(wick.groupStep, 20);
    expect(wick.highCents, 1040);
    expect(wick.lowCents, 985);
    // Even a frame with no preview cannot shrink the current cyan envelope.
    wick.observe(nextMinuteStep: 23, periodMinutes: 5,
        committedCloseCents: 1001);
    expect(wick.highCents, 1040);
    expect(wick.lowCents, 985);
    // But once a 5m bar closes, speculative prices NEVER enter committed OHLC.
    wick.observe(nextMinuteStep: 25, periodMinutes: 5,
        committedCloseCents: 1008, framePriceCents: 1009);
    expect(wick.groupStep, 25);
    expect(wick.highCents, 1009);
    expect(wick.lowCents, 1008);
  });

  test('R40 previous provisional wick lasts one 1m boundary only', () {
    final wick = TxIndicativeWickMemory();
    wick.observe(nextMinuteStep: 11, periodMinutes: 1,
        committedCloseCents: 1000, framePriceCents: 1090);
    wick.observe(nextMinuteStep: 11, periodMinutes: 1,
        committedCloseCents: 1000, framePriceCents: 950);
    // A new committed minute changes the screen, not immutable OHLC.
    wick.observe(nextMinuteStep: 12, periodMinutes: 1,
        committedCloseCents: 1020);
    expect(wick.previousGroupStep, 11);
    expect(wick.previousHighCents, 1090);
    expect(wick.previousLowCents, 950);
    expect(wick.highCents, 1020);
    // Clock jump / old snapshot must never drag an unrelated shadow.
    wick.observe(nextMinuteStep: 15, periodMinutes: 1,
        committedCloseCents: 1005);
    expect(wick.previousGroupStep, isNull);
    wick.reset();
    expect(wick.previousHighCents, isNull);
    // At an hour boundary the old hour must be accessible by group key.
    final hour = TxIndicativeWickMemory();
    hour.observe(nextMinuteStep: 178, periodMinutes: 60,
        committedCloseCents: 1000, framePriceCents: 1120);
    hour.observe(nextMinuteStep: 179, periodMinutes: 60,
        committedCloseCents: 1010, framePriceCents: 970);
    hour.observe(nextMinuteStep: 180, periodMinutes: 60,
        committedCloseCents: 1030);
    expect(hour.previousGroupStep, 120);
    expect(hour.previousHighCents, 1120);
    expect(hour.previousLowCents, 970);
  });

  test('R32 all timeframe buckets reset only at their own boundary', () {
    for (final period in [1, 5, 15, 60, 240, 1440]) {
      final wick = TxIndicativeWickMemory();
      wick.observe(nextMinuteStep: period, periodMinutes: period,
          committedCloseCents: 1000, framePriceCents: 1050);
      for (var step = period + 1; step < period * 2; step++) {
        wick.observe(nextMinuteStep: step, periodMinutes: period,
            committedCloseCents: 999, framePriceCents: 1002);
      }
      expect(wick.highCents, 1050);
      wick.observe(nextMinuteStep: period * 2, periodMinutes: period,
          committedCloseCents: 990, framePriceCents: 992);
      expect(wick.highCents, 992);
      expect(wick.lowCents, 990);
      wick.reset();
      expect(wick.highCents, isNull);
    }
  });

  test('R32 indicative extrema reject malformed floats without changing state', () {
    final wick = TxIndicativeWickMemory();
    wick.observe(nextMinuteStep: 3, periodMinutes: 5,
        committedCloseCents: 1000, framePriceCents: 1004);
    expect(() => wick.observe(nextMinuteStep: 4, periodMinutes: 5,
        committedCloseCents: 1002, framePriceCents: double.nan),
        throwsArgumentError);
    expect(wick.groupStep, 0);
    expect(wick.highCents, 1004);
  });

  test('R33 minute line extends right continuously and retains prior samples', () {
    final trace = TxTimelinePreviewTrace();
    trace.observe(nextMinuteStep: 21, seconds: 0,
        committedCloseCents: 2500, framePriceCents: 2500);
    trace.observe(nextMinuteStep: 21, seconds: 5.5,
        committedCloseCents: 2500, framePriceCents: 2504);
    trace.observe(nextMinuteStep: 21, seconds: 12.5,
        committedCloseCents: 2500, framePriceCents: 2493);
    expect(trace.minute, 21);
    expect(trace.points.map((p) => p.seconds).toList(), [0, 5.5, 12.5]);
    expect(trace.points.map((p) => p.priceCents).toList(),
        [2500, 2504, 2493]);
    // Pause with same fractional seconds does not introduce an extra kink.
    trace.observe(nextMinuteStep: 21, seconds: 12.5,
        committedCloseCents: 2500, framePriceCents: 2493);
    expect(trace.points.length, 3);
    trace.observe(nextMinuteStep: 22, seconds: 0,
        committedCloseCents: 2501, framePriceCents: 2501);
    expect(trace.points.length, 1);
    expect(trace.points.single.priceCents, 2501);
    expect(() => trace.observe(nextMinuteStep: 22,
        seconds: double.nan, committedCloseCents: 2501,
        framePriceCents: 2501), throwsArgumentError);
  });

  test('R33 frame-line sample count remains bounded at any refresh rate', () {
    final trace = TxTimelinePreviewTrace();
    for (var i = 0; i < 480; i++) {
      trace.observe(nextMinuteStep: 3, seconds: i / 10,
          committedCloseCents: 1000, framePriceCents: 1000 + (i % 17));
    }
    expect(trace.points.length, lessThanOrEqualTo(192));
    expect(trace.points.first.seconds, 0);
    expect(trace.points.last.seconds, 47.9);
    // Clock rollback resets uncommitted trace, never damages saved OHLC.
    trace.observe(nextMinuteStep: 3, seconds: 2,
        committedCloseCents: 1002, framePriceCents: 1004);
    expect(trace.points.length, 2);
    expect(trace.points.first.priceCents, 1002);
  });

  test('R37 chart samples fit minute pixel width without 300x scribbles', () {
    final trace = TxTimelinePreviewTrace();
    for (var i = 0; i < 480; i++) {
      trace.observe(nextMinuteStep: 8, seconds: i / 10.0,
          committedCloseCents: 1000,
          framePriceCents: 1000 + (i % 17) * 1.0);
    }
    final display = trace.sampledForMinuteWidth(18);
    expect(trace.points.length, greaterThan(display.length));
    expect(display.length, lessThanOrEqualTo(8));
    expect(display.first.seconds, 0);
    expect(display.last.seconds, 47.9);
    for (var i = 1; i < display.length; i++) {
      expect(display[i].seconds, greaterThan(display[i - 1].seconds));
    }
    expect(() => trace.sampledForMinuteWidth(0), throwsArgumentError);
  });

  test('R37 one-minute cyan candle includes intraminute high and low', () {
    final committed = c(80, 1000);
    final wick = TxIndicativeWickMemory();
    wick.observe(nextMinuteStep: 81, periodMinutes: 1,
        committedCloseCents: committed.closeCents.toDouble(),
        framePriceCents: 1007);
    wick.observe(nextMinuteStep: 81, periodMinutes: 1,
        committedCloseCents: committed.closeCents.toDouble(),
        framePriceCents: 995);
    final preview = TxFrameCandleProjection.fromLastCommitted(
        lastAggregated: committed, nextMinuteStep: 81,
        periodMinutes: 1, framePriceCents: 995,
        previewHighCents: wick.highCents!,
        previewLowCents: wick.lowCents!);
    expect(preview.overlaysLastCommitted, false);
    expect(preview.openCents, committed.closeCents);
    expect(preview.highCents, 1007);
    expect(preview.lowCents, 995);
    expect(committed.volumeShares, 7);
  });

  test('R33 funded NPC book revises genuine resting LP quotes each minute', () {
    final session = TxSession.freshWithAgents();
    List<String> book() => [
      for (final symbol in TxSession.symbols)
        for (final side in [TxSide.buy, TxSide.sell])
          for (final level in session.engine.depth(symbol,side))
            '${symbol}:${side.name}:${level.priceCents}:${level.quantity}',
    ];
    final first = book();
    session.nextTick();
    final second = book();
    session.nextTick();
    final third = book();
    expect(second, isNot(first));
    expect(second, isNot(third));
    session.engine.checkInvariants();
    final player = session.engine.account(TxSession.playerId);
    expect(player.cashCents, 100000000);
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
