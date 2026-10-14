/// Deterministic game-time session rules for each market mode.
///
/// The connected A-share session consumes this status as a real order/trading
/// gate. Independent modes also consume it inside the Dart venue; Rust/SQLite
/// runtime wiring remains a separate release gate.
enum TxMarketSessionState { open, breakTime, closed }

class TxMarketSessionWindow {
  const TxMarketSessionWindow({
    required this.startMinute,
    required this.endMinute,
    required this.label,
  }) : assert(startMinute >= 0 && startMinute < 1440),
       assert(endMinute > startMinute && endMinute <= 2880);

  final int startMinute;
  final int endMinute;
  final String label;
}

class TxMarketSessionStatus {
  const TxMarketSessionStatus({
    required this.state,
    required this.label,
    required this.minutesToTransition,
  });

  final TxMarketSessionState state;
  final String label;
  final int? minutesToTransition;

  bool get isOpen => state == TxMarketSessionState.open;
  bool get isBreak => state == TxMarketSessionState.breakTime;
}

class TxMarketSessionSchedule {
  const TxMarketSessionSchedule({
    required this.openWindows,
    this.breakWindows = const <TxMarketSessionWindow>[],
    this.tradingDayMask = 0x1F,
    this.alwaysOpen = false,
  });

  /// Monday is bit 0, Sunday is bit 6. Game day 1 is Monday.
  final int tradingDayMask;
  final List<TxMarketSessionWindow> openWindows;
  final List<TxMarketSessionWindow> breakWindows;
  final bool alwaysOpen;

  TxMarketSessionStatus status({
    required int gameDay,
    required int minuteOfDay,
  }) {
    _validate(gameDay, minuteOfDay);
    if (alwaysOpen) {
      return const TxMarketSessionStatus(
        state: TxMarketSessionState.open,
        label: '7×24 开市',
        minutesToTransition: null,
      );
    }
    final current = _stateAt(gameDay, minuteOfDay);
    final until = _minutesToNextStateChange(
        gameDay, minuteOfDay, current.state);
    return TxMarketSessionStatus(
      state: current.state,
      label: current.label,
      minutesToTransition: until,
    );
  }

  /// Finds the next boundary rather than walking every future minute.
  ///
  /// A selector can rebuild once per real frame while the game is running.
  /// The previous implementation checked up to 10080 individual minutes for
  /// every rebuild, even though a schedule can only change at midnight or at
  /// an open/break window boundary. Seven days is enough because the weekday
  /// mask and all supported schedules repeat weekly.
  int? _minutesToNextStateChange(
      int gameDay, int minuteOfDay, TxMarketSessionState currentState) {
    final boundaryMinutes = <int>{0};
    for (final window in <TxMarketSessionWindow>[...openWindows, ...breakWindows]) {
      boundaryMinutes.add(window.startMinute % 1440);
      boundaryMinutes.add(window.endMinute % 1440);
    }
    final boundaries = boundaryMinutes.toList()..sort();
    int? nextChange;
    for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
      final dayStart = dayOffset * 1440;
      for (final boundary in boundaries) {
        final absolute = dayStart + boundary;
        final offset = absolute - minuteOfDay;
        if (offset < 1 || offset > 10080) continue;
        final nextDay = gameDay + absolute ~/ 1440;
        final nextMinute = absolute % 1440;
        if (_stateAt(nextDay, nextMinute).state != currentState) {
          if (nextChange == null || offset < nextChange) nextChange = offset;
        }
      }
    }
    return nextChange;
  }

  TxMarketSessionStatus _stateAt(int gameDay, int minuteOfDay) {
    for (final window in openWindows) {
      if (_contains(window, gameDay, minuteOfDay)) {
        return TxMarketSessionStatus(
            state: TxMarketSessionState.open,
            label: window.label,
            minutesToTransition: null);
      }
    }
    for (final window in breakWindows) {
      if (_contains(window, gameDay, minuteOfDay)) {
        return TxMarketSessionStatus(
            state: TxMarketSessionState.breakTime,
            label: window.label,
            minutesToTransition: null);
      }
    }
    return const TxMarketSessionStatus(
        state: TxMarketSessionState.closed,
        label: '休市',
        minutesToTransition: null);
  }

  bool _contains(TxMarketSessionWindow window, int gameDay, int minute) {
    final day = (gameDay - 1) % 7;
    if (window.endMinute <= 1440) {
      return _isTradingDay(day) &&
          minute >= window.startMinute && minute < window.endMinute;
    }
    // A cross-midnight session belongs to the day on which it opens. For
    // example, Tuesday 02:00 belongs to Monday's 21:30 US session.
    final nextDayEnd = window.endMinute - 1440;
    return (minute >= window.startMinute && _isTradingDay(day)) ||
        (minute < nextDayEnd && _isTradingDay((day + 6) % 7));
  }

  bool _isTradingDay(int dayIndex) =>
      (tradingDayMask & (1 << dayIndex)) != 0;

  void _validate(int gameDay, int minuteOfDay) {
    if (gameDay < 1 || minuteOfDay < 0 || minuteOfDay >= 1440) {
      throw ArgumentError('Invalid game day or market minute');
    }
  }
}

class TxMarketSessionSchedules {
  const TxMarketSessionSchedules._();

  static const aShare = TxMarketSessionSchedule(
    openWindows: [
      TxMarketSessionWindow(
          startMinute: 570, endMinute: 690, label: '上午盘 09:30–11:30'),
      TxMarketSessionWindow(
          startMinute: 780, endMinute: 900, label: '下午盘 13:00–15:00'),
    ],
    breakWindows: [
      TxMarketSessionWindow(
          startMinute: 690, endMinute: 780, label: '午间休市 11:30–13:00'),
    ],
  );

  static const usEquity = TxMarketSessionSchedule(
    openWindows: [
      TxMarketSessionWindow(
          startMinute: 1290, endMinute: 1680, label: '美股盘 21:30–04:00'),
    ],
  );

  static const futures = TxMarketSessionSchedule(
    openWindows: [
      TxMarketSessionWindow(
          startMinute: 540, endMinute: 690, label: '期货日盘 09:00–11:30'),
      TxMarketSessionWindow(
          startMinute: 780, endMinute: 900, label: '期货日盘 13:00–15:00'),
      TxMarketSessionWindow(
          startMinute: 1260, endMinute: 1380, label: '期货夜盘 21:00–23:00'),
    ],
    breakWindows: [
      TxMarketSessionWindow(
          startMinute: 690, endMinute: 780, label: '日盘午间休市'),
    ],
  );

  static const crypto = TxMarketSessionSchedule(
    openWindows: const <TxMarketSessionWindow>[],
    alwaysOpen: true,
    tradingDayMask: 0x7F,
  );

  static const forex = TxMarketSessionSchedule(
    openWindows: [
      TxMarketSessionWindow(
          startMinute: 0, endMinute: 1440, label: '外汇工作日 5×24'),
    ],
  );
}
