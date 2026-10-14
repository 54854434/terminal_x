import 'package:flutter_test/flutter_test.dart';

import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_session_schedule.dart';

void main() {
  test('A-share session separates open, lunch break and closed states', () {
    final schedule = TxMarketProfile.aShare.schedule;
    expect(schedule.status(gameDay: 1, minuteOfDay: 600).state,
        TxMarketSessionState.open);
    expect(schedule.status(gameDay: 1, minuteOfDay: 720).state,
        TxMarketSessionState.breakTime);
    expect(schedule.status(gameDay: 1, minuteOfDay: 840).state,
        TxMarketSessionState.open);
    expect(schedule.status(gameDay: 6, minuteOfDay: 600).state,
        TxMarketSessionState.closed);
  });

  test('cross-midnight US session belongs to its opening day', () {
    final schedule = TxMarketProfile.usEquity.schedule;
    expect(schedule.status(gameDay: 1, minuteOfDay: 1320).isOpen, isTrue);
    expect(schedule.status(gameDay: 1, minuteOfDay: 1320)
        .minutesToTransition, 360);
    expect(schedule.status(gameDay: 2, minuteOfDay: 120).isOpen, isTrue);
    expect(schedule.status(gameDay: 2, minuteOfDay: 120)
        .minutesToTransition, 120);
    expect(schedule.status(gameDay: 2, minuteOfDay: 600).isOpen, isFalse);
  });

  test('crypto is always open and forex closes on the weekend', () {
    expect(TxMarketProfile.crypto.schedule
        .status(gameDay: 7, minuteOfDay: 3).isOpen, isTrue);
    expect(TxMarketProfile.forex.schedule
        .status(gameDay: 1, minuteOfDay: 600).isOpen, isTrue);
    expect(TxMarketProfile.forex.schedule
        .status(gameDay: 6, minuteOfDay: 600).isOpen, isFalse);
  });

  test('status exposes the next transition without changing the engine clock', () {
    final status = TxMarketProfile.aShare.schedule.status(
        gameDay: 1, minuteOfDay: 600);
    expect(status.minutesToTransition, 90);
    expect(status.label, '上午盘 09:30–11:30');

    final weekend = TxMarketProfile.aShare.schedule.status(
        gameDay: 5, minuteOfDay: 900);
    expect(weekend.state, TxMarketSessionState.closed);
    expect(weekend.minutesToTransition, 3990);
  });
}
