/// Limits only chart paint notifications, never simulation clock progression.
/// Feed each vsync delta to TxContinuousFlowClock independently of this gate.
class TxFrameRenderGate {
  TxFrameRenderGate({this.minimumInterval = const Duration(milliseconds: 14)}) {
    if (minimumInterval.inMicroseconds <= 0) {
      throw ArgumentError.value(minimumInterval, 'minimumInterval');
    }
  }
  final Duration minimumInterval;
  int? _lastPaintMicros;
  void reset() => _lastPaintMicros = null;
  bool shouldPaint(Duration tickerElapsed, {bool force = false}) {
    if (tickerElapsed.isNegative) {
      throw ArgumentError.value(tickerElapsed, 'tickerElapsed');
    }
    final now = tickerElapsed.inMicroseconds;
    final last = _lastPaintMicros;
    if (force || last == null || now < last ||
        now - last >= minimumInterval.inMicroseconds) {
      _lastPaintMicros = now;
      return true;
    }
    return false;
  }
}
