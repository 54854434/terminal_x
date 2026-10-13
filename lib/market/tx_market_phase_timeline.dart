/// Read-only scripted simulation-regime events derived exclusively from
/// deterministic TxSession.marketRegime. These are GAME PHASE annotations:
/// no real-world news, price promise, fake trade or SQLite state change.
import '../engine/tx_session.dart';

class TxMarketPhaseEvent {
  const TxMarketPhaseEvent({required this.minute, required this.symbol,
    required this.regime, required this.label});
  final int minute;
  final String symbol;
  final int regime;
  final String label;
}

class TxMarketPhaseTimeline {
  const TxMarketPhaseTimeline._();

  static String regimeLabel(int regime) => switch (regime) {
    0 => '上行趋势',
    1 => '区间震荡',
    2 => '下行趋势',
    3 => '高波动',
    _ => throw ArgumentError.value(regime, 'regime'),
  };

  /// At step 0 or 1..20 no regime has switched yet. Phase N starts at
  /// game minute (N*20+1); never show a transition from the future.
  /// Bounded memory O(limit), independent of game age and fill history.
  static List<TxMarketPhaseEvent> recent({required int currentStep,
    int limit = 6}) {
    if (currentStep < 0 || limit < 1) {
      throw ArgumentError('Invalid game time or event limit');
    }
    if (currentStep <= TxSession.marketRegimeMinutes) {
      return const <TxMarketPhaseEvent>[];
    }
    final events = <TxMarketPhaseEvent>[];
    final lastBoundary = (currentStep - 1) ~/ TxSession.marketRegimeMinutes;
    for (var group = lastBoundary; group >= 1 && events.length < limit; group--) {
      final minute = group * TxSession.marketRegimeMinutes + 1;
      for (var i = 0; i < TxSession.symbols.length && events.length < limit; i++) {
        final regime = TxSession.marketRegime(minute, i);
        events.add(TxMarketPhaseEvent(minute: minute,
          symbol: TxSession.symbols[i], regime: regime,
          label: regimeLabel(regime)));
      }
    }
    return List<TxMarketPhaseEvent>.unmodifiable(events);
  }
}
