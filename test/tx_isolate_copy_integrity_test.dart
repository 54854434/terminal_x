import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

void main() {
  test('worker receives copied session; previous committed revision stays immutable', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final trading = TxTradingService(db,
          initialSessionFactory: TxSession.freshWithAgents);
      final old = await trading.open();
      final first = old.session;
      final firstJson = first.exportJson();
      final next = await trading.nextTick();
      expect(first.step, 0);
      expect(first.exportJson(), firstJson);
      expect(old.revision, 1);
      expect(next.session.step, 1);
      expect(next.revision, 2);
      expect(next.session.engine.fills.length,
          greaterThanOrEqualTo(first.engine.fills.length));
      next.session.engine.checkInvariants();
      final restored = (await db.readCurrent())!;
      expect(restored.sha256, next.sha256);
      expect(restored.session.exportJson(), next.session.exportJson());
    } finally {
      await db.close();
    }
  });

  test('existing account open does not evaluate fresh factory', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final first = TxTradingService(db,
          initialSessionFactory: TxSession.freshWithAgents);
      final stored = await first.open();
      final reopened = TxTradingService(db,
          initialSessionFactory: () => throw StateError('unexpected reset'));
      final loaded = await reopened.open();
      expect(loaded.sha256, stored.sha256);
      expect(loaded.revision, stored.revision);
      expect(loaded.session.engine.account(TxSession.playerId).cashCents,
          stored.session.engine.account(TxSession.playerId).cashCents);
    } finally {
      await db.close();
    }
  });
}
