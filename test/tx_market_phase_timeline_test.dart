import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_market_phase_timeline.dart';

void main() {
  test('no future events before first completed phase', () {
    expect(TxMarketPhaseTimeline.recent(currentStep: 0), isEmpty);
    expect(TxMarketPhaseTimeline.recent(currentStep: 20), isEmpty);
    expect(TxMarketPhaseTimeline.recent(currentStep: 21).length, 2);
    expect(TxMarketPhaseTimeline.recent(currentStep: 21)
      .every((e) => e.minute == 21), isTrue);
  });
  test('phase annotations come from deterministic session algorithm', () {
    final events = TxMarketPhaseTimeline.recent(currentStep: 81);
    expect(events.length, 6);
    for (final event in events) {
      expect(event.minute <= 81, isTrue);
      final index = TxSession.symbols.indexOf(event.symbol);
      expect(index >= 0, isTrue);
      expect(event.regime, TxSession.marketRegime(event.minute, index));
      expect(event.label, TxMarketPhaseTimeline.regimeLabel(event.regime));
    }
    expect(events.first.minute, 81);
  });
  test('bounded event history is newest first and immutable', () {
    final history = TxMarketPhaseTimeline.recent(
      currentStep: 1000000, limit: 3);
    expect(history.length, 3);
    expect(history.first.minute >= history.last.minute, isTrue);
    expect(() => history.clear(), throwsUnsupportedError);
  });
  test('invalid time and result bounds fail closed', () {
    expect(() => TxMarketPhaseTimeline.recent(currentStep: -1),
      throwsArgumentError);
    expect(() => TxMarketPhaseTimeline.recent(currentStep: 21, limit: 0),
      throwsArgumentError);
    expect(() => TxMarketPhaseTimeline.regimeLabel(4),
      throwsArgumentError);
  });
}
