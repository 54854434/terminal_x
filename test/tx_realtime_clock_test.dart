import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_realtime_clock.dart';

void main() {
  test('1x changes precisely one game second per real second', () {
    expect(TxRealtimeClock.gameSecondsPerRealSecond(1), 1);
    expect(TxRealtimeClock.remainderSeconds(0, 1), 1);
    expect(TxRealtimeClock.minuteCommits(0, 1), 0);
    expect(TxRealtimeClock.minuteCommits(59, 1), 1);
    expect(TxRealtimeClock.remainderSeconds(59, 1), 0);
  });

  test('all supported speeds add seconds without multiple DB commits per second', () {
    expect(TxRealtimeClock.speeds, [1, 2, 5, 10, 15, 30, 60]);
    for (final speed in TxRealtimeClock.speeds) {
      for (var fraction = 0; fraction < 60; fraction++) {
        expect(TxRealtimeClock.minuteCommits(fraction, speed), lessThanOrEqualTo(1));
        expect(TxRealtimeClock.remainderSeconds(fraction, speed),
            (fraction + speed) % 60);
      }
    }
    expect(() => TxRealtimeClock.gameSecondsPerRealSecond(0), throwsArgumentError);
    expect(() => TxRealtimeClock.gameSecondsPerRealSecond(120), throwsArgumentError);
    expect(() => TxRealtimeClock.remainderSeconds(60, 1), throwsArgumentError);
  });

  test('24h clock with independent simulated day and second precision', () {
    expect(TxRealtimeClock.gameDay(0, 0), 1);
    expect(TxRealtimeClock.hhmmss(0, 0), '09:30:00');
    expect(TxRealtimeClock.hhmmss(0, 59), '09:30:59');
    expect(TxRealtimeClock.hhmmss(1, 0), '09:31:00');
    expect(TxRealtimeClock.hhmmss(869, 59), '23:59:59');
    expect(TxRealtimeClock.hhmmss(870, 0), '00:00:00');
    expect(TxRealtimeClock.gameDay(870, 0), 2);
    expect(TxRealtimeClock.hhmmss(1440, 0), '09:30:00');
    expect(TxRealtimeClock.gameDay(1440, 0), 2);
    expect(() => TxRealtimeClock.gameDay(-1, 0), throwsArgumentError);
    expect(() => TxRealtimeClock.hhmmss(1, 60), throwsArgumentError);
  });

  test('freeze clock after a failed commit: do not display uncommitted time', () {
    final beforeMinutes = 10;
    final beforeSeconds = 50;
    final speed = 30;
    expect(TxRealtimeClock.minuteCommits(beforeSeconds, speed), 1);
    // When the caller cannot commit minute 11, both values are untouched.
    expect(TxRealtimeClock.hhmmss(beforeMinutes, beforeSeconds), '09:40:50');
    expect(TxRealtimeClock.remainderSeconds(beforeSeconds, speed), 20);
    // After successful commit alone the UI may show 09:41:20.
    expect(TxRealtimeClock.hhmmss(beforeMinutes + 1, 20), '09:41:20');
  });
}
