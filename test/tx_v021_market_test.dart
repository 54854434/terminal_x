import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_simulation_clock.dart';

void main() {
  test('one game minute per committed tick, 24 hour rollover', () {
    expect(TxSimulationClock.hhmm(0), '09:30');
    expect(TxSimulationClock.hhmm(1), '09:31');
    expect(TxSimulationClock.hhmm(869), '23:59');
    expect(TxSimulationClock.hhmm(870), '00:00');
    expect(TxSimulationClock.gameDay(869), 1);
    expect(TxSimulationClock.gameDay(870), 2);
    expect(TxSimulationClock.hhmm(1440), '09:30');
    expect(TxSimulationClock.gameDay(1440), 2);
    expect(() => TxSimulationClock.hhmm(-1), throwsArgumentError);
  });

  test('speed changes wall-clock delay, not number of minutes or backlog', () {
    expect(TxSimulationClock.delayForSpeed(1).inMilliseconds, 5000);
    expect(TxSimulationClock.delayForSpeed(5).inMilliseconds, 1000);
    expect(TxSimulationClock.delayForSpeed(10).inMilliseconds, 500);
    expect(() => TxSimulationClock.delayForSpeed(2), throwsArgumentError);
  });

  test('market moves are deterministic, visible, and not old 7-step loop', () {
    final a = TxSession.fresh();
    final b = TxSession.fresh();
    final prices = <int>[a.lastPrice('SIM-A01')];
    for (var i = 0; i < 28; i++) {
      a.nextTick();
      b.nextTick();
      prices.add(a.lastPrice('SIM-A01'));
      expect(a.exportJson(), b.exportJson());
    }
    expect(prices.toSet().length, greaterThan(8));
    expect(prices[7], isNot(prices[0]));
    expect(prices.last, isNot(prices.first));
    a.engine.checkInvariants();
    final restored = TxSession.importJson(a.exportJson());
    a.nextTick();
    restored.nextTick();
    expect(a.exportJson(), restored.exportJson());
  });
}
