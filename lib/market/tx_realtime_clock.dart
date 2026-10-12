/// A game-time second advances once per real second at 1x speed.
/// Economic events remain one atomic, validated SQLite commit per GAME minute.
/// No skipped minute, retroactive catch-up or false trade volume.
class TxRealtimeClock {
  const TxRealtimeClock._();

  static const int firstMinuteOfDay = 9 * 60 + 30;
  static const int secondsPerMinute = 60;
  static const int secondsPerDay = 86400;
  static const List<int> speeds = [1, 2, 5, 10, 15, 30, 60];

  static int validateSpeed(int speed) {
    if (!speeds.contains(speed)) throw ArgumentError.value(speed, 'speed');
    return speed;
  }

  /// The 1-second UI cadence is independent of the 1-minute SQLite cadence.
  /// A speed of at most 60 guarantees at most one SQLite minute per callback.
  static int gameSecondsPerRealSecond(int speed) => validateSpeed(speed);

  static int minuteCommits(int fractionalGameSeconds, int speed) {
    if (fractionalGameSeconds < 0 || fractionalGameSeconds >= 60) {
      throw ArgumentError.value(fractionalGameSeconds, 'fractionalGameSeconds');
    }
    return (fractionalGameSeconds + gameSecondsPerRealSecond(speed)) ~/ 60;
  }

  static int remainderSeconds(int fractionalGameSeconds, int speed) {
    minuteCommits(fractionalGameSeconds, speed);
    return (fractionalGameSeconds + speed) % 60;
  }

  static int gameDay(int committedMinutes, int fractionalSeconds) {
    final seconds = _secondsFromOrigin(committedMinutes, fractionalSeconds);
    return seconds ~/ secondsPerDay + 1;
  }

  static String hhmmss(int committedMinutes, int fractionalSeconds) {
    var seconds = _secondsFromOrigin(committedMinutes, fractionalSeconds);
    seconds %= secondsPerDay;
    final hour = seconds ~/ 3600;
    final minute = (seconds % 3600) ~/ 60;
    final second = seconds % 60;
    return '${_two(hour)}:${_two(minute)}:${_two(second)}';
  }

  static int _secondsFromOrigin(int committedMinutes, int fractionalSeconds) {
    if (committedMinutes < 0 || fractionalSeconds < 0 || fractionalSeconds >= 60) {
      throw ArgumentError('Invalid committed minute / fractional second');
    }
    return firstMinuteOfDay * 60 + committedMinutes * 60 + fractionalSeconds;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
