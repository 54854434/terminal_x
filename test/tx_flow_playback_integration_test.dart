import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_continuous_flow_clock.dart';
import '../lib/market/tx_speed_feedback.dart';

void main() {
  test('100x renders intermediate steps before first durable minute', () {
    final flow = TxContinuousFlowClock(speed: 100)..resume();
    var previous = 0;
    for (var frame = 0; frame < 35; frame++) {
      final result = flow.advance(const Duration(milliseconds: 16));
      expect(result.needsMinuteCommit, isFalse);
      expect(result.second, greaterThanOrEqualTo(previous));
      expect(result.second, lessThan(60));
      previous = result.second;
    }
    expect(previous, greaterThan(40));
    expect(flow.advance(const Duration(milliseconds: 40))
        .needsMinuteCommit, isTrue);
    for (var frame = 0; frame < 100; frame++) {
      expect(flow.advance(const Duration(seconds: 1))
          .needsMinuteCommit, isFalse);
    }
    flow.pause();
    flow.completeMinuteCommit();
    expect(flow.running, isFalse);
    expect(flow.second, 0);
  });

  test('storage stall never catches up imaginary elapsed minutes', () {
    final flow = TxContinuousFlowClock(speed: 3600)..resume();
    expect(flow.advance(const Duration(milliseconds: 20))
        .needsMinuteCommit, isTrue);
    for (var i = 0; i < 100; i++) {
      // Many frame callbacks and many apparent minutes of wall time:
      // zero new revisions while a single SQLite commit is outstanding.
      final stalled = flow.advance(const Duration(seconds: 5));
      expect(stalled.needsMinuteCommit, isFalse);
      expect(stalled.isWaitingForStorage, isTrue);
    }
    flow.completeMinuteCommit();
    expect(flow.second, 0);
    expect(flow.advance(const Duration(microseconds: 100))
        .needsMinuteCommit, isFalse);
  });

  test('storage ambiguity disables future game-clock progression', () {
    final flow = TxContinuousFlowClock(speed: 120)..resume();
    expect(flow.advance(const Duration(seconds: 1)).needsMinuteCommit, isTrue);
    flow.storageFailed();
    expect(flow.running, isFalse);
    expect(flow.faulted, isTrue);
    expect(flow.advance(const Duration(days: 1)).needsMinuteCommit, isFalse);
    expect(() => flow.resume(), throwsStateError);
    expect(() => flow.setSpeed(100), throwsStateError);
    expect(() => flow.completeMinuteCommit(), throwsStateError);
  });

  test('pause cannot issue an additional queued write', () {
    final flow = TxContinuousFlowClock(speed: 3600)..resume();
    expect(flow.advance(const Duration(milliseconds: 17))
        .needsMinuteCommit, isTrue);
    flow.pause();
    expect(flow.advance(const Duration(minutes: 2))
        .needsMinuteCommit, isFalse);
    expect(() => flow.resume(), throwsStateError);
    flow.completeMinuteCommit();
    expect(flow.advance(const Duration(minutes: 2))
        .needsMinuteCommit, isFalse);
  });

  test('manual step can drop preview only after pause', () {
    final flow = TxContinuousFlowClock(speed: 100)..resume();
    flow.advance(const Duration(milliseconds: 270));
    expect(() => flow.resetProvisional(), throwsStateError);
    flow.pause();
    flow.resetProvisional();
    expect(flow.second, 0);
  });

  test('indexed fill-ledger audit preserves corruption rejection', () {
    final e = TxEngine()
      ..registerAccount('buyer', cashCents: 100000)
      ..registerAccount('seller', cashCents: 0, shares: {'ABC': 20});
    e.place(id: 'ask', ownerId: 'seller', symbol: 'ABC',
        side: TxSide.sell, kind: TxKind.limit,
        quantity: 10, limitPriceCents: 100);
    e.place(id: 'buy', ownerId: 'buyer', symbol: 'ABC',
        side: TxSide.buy, kind: TxKind.market, quantity: 10);
    expect(e.fills.length, 1);
    e.checkInvariants();
    final recovered = TxEngine.importJson(e.exportJson());
    expect(recovered.exportJson(), e.exportJson());
    final broken = jsonDecode(e.exportJson()) as Map<String, dynamic>;
    final lines = broken['ledger'] as List<dynamic>;
    final firstLinked = lines.cast<Map<String, dynamic>>().firstWhere(
        (l) => l['fillId'] != null);
    firstLinked['fillId'] = null; // Cash/share remain unchanged.
    expect(() => TxEngine.importJson(jsonEncode(broken)), throwsStateError);
  });

  test('read-only fill cursor matches snapshots and rejects invalid offset', () {
    final e = TxEngine()
      ..registerAccount('buyer', cashCents: 100000)
      ..registerAccount('seller', cashCents: 0, shares: {'ABC': 5});
    e.place(id: 'ask', ownerId: 'seller', symbol: 'ABC', side: TxSide.sell,
        kind: TxKind.limit, quantity: 5, limitPriceCents: 100);
    e.place(id: 'buy', ownerId: 'buyer', symbol: 'ABC', side: TxSide.buy,
        kind: TxKind.market, quantity: 5);
    expect(e.fillCount, 1);
    expect(e.fillAt(0).id, e.fills.single.id);
    expect(() => e.fillAt(1), throwsRangeError);
    final restored = TxEngine.importJson(e.exportJson());
    expect(restored.fillCount, e.fillCount);
    expect(restored.fillAt(0).priceCents, e.fillAt(0).priceCents);
  });

  test('session quote access preserves executed fills and restart', () {
    final s = TxSession.fresh();
    final previous = s.lastPrice('SIM-A01');
    expect(s.currentMinuteFills, isEmpty);
    final order = s.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 2);
    expect(order.filled, 2);
    expect(s.currentMinuteFills, isNotEmpty);
    expect(s.currentMinuteFills.fold<int>(0, (n, f) => n + f.quantity), 2);
    expect(s.lastPrice('SIM-A01'), isNot(previous));
    final roundTrip = TxSession.importJson(s.exportJson());
    expect(roundTrip.currentMinuteFills.length, s.currentMinuteFills.length);
    expect(roundTrip.lastPrice('SIM-A01'), s.lastPrice('SIM-A01'));
    expect(roundTrip.engine.fillCount, s.engine.fillCount);
  });

  test('requested 3600x does not masquerade as committed throughput', () {
    final window = TxCommittedSpeedWindow();
    window.record(elapsedMilliseconds: 0, minute: 0);
    window.record(elapsedMilliseconds: 2000, minute: 1);
    expect(window.achievedMultiplier, 30);
    expect(TxContinuousFlowClock.uiSpeeds, containsAll([100, 120, 600, 3600]));
  });
}
