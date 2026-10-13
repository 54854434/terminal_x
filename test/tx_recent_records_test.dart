import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';

void main() {
  test('bounded recent player fills retain newest-first real execution order', () {
    final session = TxSession.fresh();
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 2);
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 3);
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.sell,
        kind: TxKind.market, quantity: 1);
    final all = session.playerFills;
    expect(all.length, greaterThanOrEqualTo(2));
    expect(session.recentPlayerFills(limit: 2).map((f) => f.id).toList(),
        all.take(2).map((f) => f.id).toList());
    expect(session.recentPlayerFills(limit: 100).map((f) => f.id).toList(),
        all.map((f) => f.id).toList());
    final restored = TxSession.importJson(session.exportJson());
    expect(restored.recentPlayerFills(limit: 2).map((f) => f.id).toList(),
        all.take(2).map((f) => f.id).toList());
    restored.engine.checkInvariants();
  });

  test('empty and invalid bounded player fill queries fail safely', () {
    final session = TxSession.fresh();
    expect(session.recentPlayerFills(limit: 1), isEmpty);
    expect(session.playerFills, isEmpty);
    expect(() => session.recentPlayerFills(limit: 0), throwsArgumentError);
    expect(() => session.recentPlayerFills(limit: -5), throwsArgumentError);
  });

  test('read-only bounded history never modifies saved economic state', () {
    final session = TxSession.fresh();
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 4);
    final original = session.exportJson();
    for (var i = 0; i < 10; i++) {
      session.recentPlayerFills(limit: 1);
    }
    expect(session.exportJson(), original);
  });
}
