/// Deterministic 24-hour *game* clock. One committed tick = one game minute.
/// No device clock affects orders or the simulated date.
class TxSimulationClock {
  const TxSimulationClock._();
  static const startMinutes = 9 * 60 + 30;
  static const stepsPerDay = 24 * 60;
  static const int minutesPerTick = 1;

  static int gameDay(int step) {
    if (step < 0) throw ArgumentError.value(step, 'step');
    return 1 + (startMinutes + step) ~/ stepsPerDay;
  }

  static String hhmm(int step) {
    if (step < 0) throw ArgumentError.value(step, 'step');
    final minuteOfDay = (startMinutes + step) % stepsPerDay;
    final hour = minuteOfDay ~/ 60;
    final minute = minuteOfDay % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// 1x = one game minute each 5 real seconds; 5x = every 1s;
  /// 10x = every 0.5s. Slow storage slows the game; no skipped minutes.
  static Duration delayForSpeed(int speed) {
    if (speed != 1 && speed != 5 && speed != 10) {
      throw ArgumentError.value(speed, 'speed');
    }
    return Duration(milliseconds: 5000 ~/ speed);
  }
}
