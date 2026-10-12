import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_live_candles.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';
import '../lib/widgets/tx_candle_chart.dart';

void main() {
  test('background evaluation keeps revisions atomic and replayable', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxTradingService(db,
          initialSessionFactory: TxSession.freshWithAgents);
      await service.open();
      final candles = TxLiveCandles.fromVerifiedHistory(await db.readHistory());
      for (var i = 0; i < 12; i++) {
        final before = service.current;
        await service.nextTick();
        candles.addCommit(before, service.current);
        expect(service.current.revision, before.revision + 1);
      }
      expect(service.current.session.step, 12);
      final restored = (await db.readCurrent())!;
      expect(restored.sha256, service.current.sha256);
      expect(restored.session.engine.fills.length,
          service.current.session.engine.fills.length);
      restored.session.engine.checkInvariants();
      expect(candles.forSymbol('SIM-A01').last.volumeShares,
          greaterThanOrEqualTo(0));
    } finally {
      await db.close();
    }
  });

  test('parallel minute requests cannot double-commit one revision', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxTradingService(db,
          initialSessionFactory: TxSession.freshWithAgents);
      await service.open();
      final first = service.nextTick();
      await expectLater(service.nextTick(), throwsStateError);
      await first;
      expect(service.current.revision, 2);
      expect(service.current.session.step, 1);
    } finally {
      await db.close();
    }
  });

  testWidgets('flat candles and provisional quote remain distinguishable',
      (tester) async {
    final candles = [
      const TxCandle(step: 0, openCents: 1000, highCents: 1000,
          lowCents: 1000, closeCents: 1000, volumeShares: 0),
      const TxCandle(step: 1, openCents: 1000, highCents: 1012,
          lowCents: 992, closeCents: 1004, volumeShares: 5),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxCandleChart(candles: candles, indicativePriceCents: 1008))));
    expect(find.textContaining('模拟 K 线'), findsOneWidget);
    expect(find.textContaining('指示价（非成交）'), findsOneWidget);
    expect(find.textContaining('无影线'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxCandleChart(candles: candles, indicativePriceCents: 995))));
    expect(tester.takeException(), isNull);
    expect(candles.first.volumeShares, 0); // visual preview never changes history
    expect(candles.last.highCents, 1012);
    expect(candles.last.lowCents, 992);
    final differentSymbol = [const TxCandle(step: 1, openCents: 2500,
        highCents: 2503, lowCents: 2498, closeCents: 2501,
        volumeShares: 4)];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxCandleChart(candles: differentSymbol,
            indicativePriceCents: 2502))));
    expect(tester.takeException(), isNull);
  });
}
