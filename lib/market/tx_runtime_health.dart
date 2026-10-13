/// Diagnostic estimate, not a guarantee of sustained frame rate or speed.
/// End-to-end committed-minute p95 includes worker matching and SQLite I/O.
class TxRuntimeHealth {
  const TxRuntimeHealth._({required this.targetSpeed,
    required this.p95Milliseconds,required this.sampleCount,
    required this.budgetMilliseconds,required this.budgetExceeded});
  final int targetSpeed;
  final int p95Milliseconds;
  final int sampleCount;
  final double budgetMilliseconds;
  final bool? budgetExceeded;
  double get budgetFraction => p95Milliseconds/budgetMilliseconds;

  static TxRuntimeHealth evaluate({required int speed,
    required int sampleCount,required int p95Milliseconds}) {
    if(speed<1 || speed>3600 || sampleCount<0 || p95Milliseconds<0) {
      throw ArgumentError('Invalid speed or latency sample');
    }
    final budget=60000.0/speed;
    return TxRuntimeHealth._(targetSpeed:speed,
      sampleCount:sampleCount,p95Milliseconds:p95Milliseconds,
      budgetMilliseconds:budget,
      budgetExceeded:sampleCount<5 ? null : p95Milliseconds>budget);
  }
}
