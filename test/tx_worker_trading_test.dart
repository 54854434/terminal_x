import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

void main() {
  test('worker place/cancel preserves old revision and commits once', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxTradingService(db);
      final before = await service.open();
      final order = await service.place(symbol: TxSession.symbols.first,
        side: TxSide.buy, kind: TxKind.limit, quantity: 3,
        limitPriceCents: 700);
      expect(before.revision, 1);
      expect(before.session.playerOrders, isEmpty);
      expect(service.current.revision, 2);
      expect(service.current.session.engine.order(order.id).status, TxStatus.open);
      final cancelled = await service.cancel(order.id);
      expect(cancelled.status, TxStatus.cancelled);
      expect(service.current.revision, 3);
      final restored = (await db.readCurrent())!;
      expect(restored.session.engine.account(TxSession.playerId)
        .reservedCashCents, 0);
      restored.session.engine.checkInvariants();
    } finally { await db.close(); }
  });

  test('single-writer guard rejects concurrent action during isolate work', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxTradingService(db);
      await service.open();
      final pending = service.place(symbol: TxSession.symbols.first,
        side: TxSide.buy, kind: TxKind.limit, quantity: 1,
        limitPriceCents: 700);
      await expectLater(service.nextTick(), throwsStateError);
      final result = await pending;
      expect(result.status, TxStatus.open);
      expect(service.current.revision, 2);
    } finally { await db.close(); }
  });

  test('verified minute tape has no imaginary transactions', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final service = TxTradingService(db);
      await service.open(); // Legacy test book: no active NPC accounts.
      final tape = await service.nextTickWithTape();
      expect(tape.minute, 1);
      expect(tape.observations, isEmpty);
      expect(service.current.revision, 2);
    } finally { await db.close(); }
  });
}
