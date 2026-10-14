import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';

void main() {
  test('A-share session status is shared by order gate and UI time', () {
    expect(TxSession.marketSessionStatusAt(committedStep: 0).isOpen, isTrue);
    expect(TxSession.marketSessionStatusAt(committedStep: 120).isBreak,
        isTrue);
    expect(TxSession.marketSessionStatusAt(committedStep: 210).isOpen,
        isTrue);
    expect(TxSession.marketSessionStatusAt(committedStep: 330).isOpen,
        isFalse);
    expect(TxSession.marketSessionStatusAt(
        committedStep: 0, fractionalSeconds: 59).label,
        '上午盘 09:30–11:30');
  });

  test('break boundary withdraws participant liquidity and rejects new orders',
      () {
    final session = TxSession.freshWithAgents()..step = 119;
    final before = List<int>.of(session.referenceCents);

    session.marketPulse(15);
    expect(session.lastPulseSecond, 15);
    expect(session.currentMinuteFills, isEmpty);

    session.nextTick();
    expect(session.step, 120);
    expect(session.referenceCents, before);
    expect(session.currentMinuteFills, isEmpty);
    expect(session.engine.activeOrders.where((order) =>
        order.ownerId.startsWith('NPC_') || order.ownerId.startsWith('LP_')),
        isEmpty);
    expect(() => session.placePlayer(
      symbol: TxSession.symbols.first,
      side: TxSide.buy,
      kind: TxKind.market,
      quantity: 1,
    ), throwsStateError);
    session.engine.checkInvariants();
  });

  test('participant flow resumes at the afternoon open', () {
    final session = TxSession.freshWithAgents()..step = 209;
    session.nextTick();
    expect(session.step, 210);
    expect(session.marketSessionStatus.isOpen, isTrue);
    expect(session.currentMinuteFills, isNotEmpty);
    session.engine.checkInvariants();
  });

  test('closed fast-forward stops before the next open without prints', () {
    final session = TxSession.freshWithAgents();
    final order = session.placePlayer(
      symbol: TxSession.symbols.first,
      side: TxSide.buy,
      kind: TxKind.limit,
      quantity: 1,
      limitPriceCents: 800,
    );
    final beforeReference = List<int>.of(session.referenceCents);
    session.step = 120;

    final skipped = session.fastForwardClosed();

    expect(skipped, 89);
    expect(session.step, 209);
    expect(session.marketSessionStatus.isOpen, isFalse);
    expect(TxSession.marketSessionStatusAt(committedStep: 210).isOpen,
        isTrue);
    expect(session.referenceCents, beforeReference);
    expect(session.currentMinuteFills, isEmpty);
    expect(session.engine.order(order.id).status, TxStatus.open);
    expect(session.engine.activeOrders.where((item) =>
        item.ownerId.startsWith('NPC_') || item.ownerId.startsWith('LP_')),
        isEmpty);
    session.engine.checkInvariants();
  });
}
