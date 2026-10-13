import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

void main() {
  late TxSqliteStore db;
  late TxTradingService service;

  setUp(() {
    db = TxSqliteStore(NativeDatabase.memory());
    service = TxTradingService(db);
  });
  tearDown(() async => db.close());

  test('new SQLite trading session is created exactly once', () async {
    final first = await service.open();
    expect(first.revision, 1);
    expect(first.session.step, 0);
    expect(first.session.playerOrders, isEmpty);
    expect(first.session.playerFills, isEmpty);
    final second = await service.open();
    expect(second.sha256, first.sha256);
    final record = await db.customSelect(
      'SELECT COUNT(*) AS n FROM migration_records',
    ).getSingle();
    expect(record.read<int>('n'), 0);
    final snapshots = await db.customSelect(
      'SELECT COUNT(*) AS n FROM snapshots',
    ).getSingle();
    expect(snapshots.read<int>('n'), 1);
  });

  test('market buy is durable with exact fills and cash movement', () async {
    final original = await service.open();
    final before = original.session.engine.account(TxSession.playerId).cashCents;
    final order = await service.place(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.market,
      quantity: 2,
    );
    expect(order.status, TxStatus.filled);
    expect(service.current.revision, 2);
    final stored = await db.readCurrent();
    expect(stored!.session.engine.account(TxSession.playerId).cashCents,
        before - 2 * 1001);
    expect(stored.session.engine.account(TxSession.playerId)
        .sharesOf(TxSession.symbols[0]), 2);
    expect(stored.session.playerFills.length, 1);
    stored.session.engine.checkInvariants();
  });

  test('resting buy freeze and cancellation both commit to SQLite', () async {
    await service.open();
    final order = await service.place(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.limit,
      quantity: 5,
      limitPriceCents: 800,
    );
    expect(order.status, TxStatus.open);
    expect((await db.readCurrent())!.session.engine
        .account(TxSession.playerId).reservedCashCents, 4000);
    await service.cancel(order.id);
    final restored = (await db.readCurrent())!;
    expect(restored.revision, 3);
    expect(restored.session.engine.account(TxSession.playerId)
        .reservedCashCents, 0);
    expect(restored.session.playerOrders.first.status, TxStatus.cancelled);
  });

  test('resting sell freeze releases after cancellation', () async {
    await service.open();
    await service.place(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.market, quantity: 2);
    final sell = await service.place(symbol: TxSession.symbols[0],
        side: TxSide.sell, kind: TxKind.limit, quantity: 1,
        limitPriceCents: 1200);
    expect(sell.status, TxStatus.open);
    expect((await db.readCurrent())!.session.engine.account(TxSession.playerId)
        .reservedSharesOf(TxSession.symbols[0]), 1);
    await service.cancel(sell.id);
    expect((await db.readCurrent())!.session.engine.account(TxSession.playerId)
        .reservedSharesOf(TxSession.symbols[0]), 0);
  });

  test('insufficient shares rejects without changing assets', () async {
    await service.open();
    final startingCash = service.current.session.engine
        .account(TxSession.playerId).cashCents;
    final rejected = await service.place(symbol: TxSession.symbols[0],
        side: TxSide.sell, kind: TxKind.market, quantity: 1);
    expect(rejected.status, TxStatus.rejected);
    expect((await db.readCurrent())!.session.engine
        .account(TxSession.playerId).cashCents, startingCash);
  });

  test('R41 stage timings publish only after durable minute and never mutate save',
      () async {
    await service.open();
    expect(service.lastTickTimings, isNull);
    final before = service.current;
    await service.nextTick();
    final stages = service.lastTickTimings;
    expect(stages, isNotNull);
    expect(stages!.market.isNegative, isFalse);
    expect(stages.sqlite.isNegative, isFalse);
    expect(stages.acknowledgement.isNegative, isFalse);
    expect(service.current.revision, before.revision + 1);
    expect((await db.readCurrent())!.session.exportJson(),
        service.current.session.exportJson());
  });

  test('ticks persist and new service instance reads same account', () async {
    await service.open();
    await service.nextTick();
    final newReader = TxTradingService(db);
    final existing = await newReader.open();
    expect(existing.revision, 2);
    expect(existing.session.step, 1);
    await newReader.nextTick();
    expect((await db.readCurrent())!.session.step, 2);
  });

  test('initializeFresh never overwrites an existing changed account', () async {
    await service.open();
    await service.nextTick();
    final stored = await db.initializeFresh(TxSession.fresh());
    expect(stored.revision, 2);
    expect(stored.session.step, 1);
    final snapshots = await db.customSelect(
      'SELECT COUNT(*) AS n FROM snapshots',
    ).getSingle();
    expect(snapshots.read<int>('n'), 2);
  });

  test('corrupt active snapshot fails closed without creating a new one', () async {
    await service.open();
    await db.customStatement("UPDATE snapshots SET sha256 = 'BROKEN'");
    final reopened = TxTradingService(db);
    await expectLater(reopened.open(), throwsStateError);
    expect(reopened.blocked, isTrue);
    final row = await db.customSelect('SELECT COUNT(*) AS n FROM snapshots')
        .getSingle();
    expect(row.read<int>('n'), 1);
  });

  test('simulated SQLite save failure blocks further trades', () async {
    await db.close();
    var writes = 0;
    db = TxSqliteStore(NativeDatabase.memory(), testCheckpoint: (point) {
      if (point == 'after_session_insert' && ++writes == 2) {
        throw StateError('injected commit failure');
      }
    });
    service = TxTradingService(db);
    await service.open();
    await expectLater(service.nextTick(), throwsStateError);
    expect(service.blocked, isTrue);
    expect((await db.readCurrent())!.revision, 1);
    expect((await db.readCurrent())!.session.step, 0);
    await expectLater(service.nextTick(), throwsStateError);
  });

  test('Android-style file close and reopen preserves trade and clock', () async {
    final folder = await Directory.systemTemp.createTemp('terminal_x_v01d_');
    final file = File('${folder.path}/fresh.sqlite');
    TxSqliteStore? disk;
    try {
      disk = TxSqliteStore(NativeDatabase(file));
      final trader = TxTradingService(disk);
      await trader.open();
      await trader.place(symbol: TxSession.symbols[0],
          side: TxSide.buy, kind: TxKind.market, quantity: 1);
      await trader.nextTick();
      final checksum = trader.current.sha256;
      await disk.close();
      disk = null;
      disk = TxSqliteStore(NativeDatabase(file));
      final restored = await TxTradingService(disk).open();
      expect(restored.revision, 3);
      expect(restored.session.step, 1);
      expect(restored.session.playerFills.length, 1);
      expect(restored.sha256, checksum);
      restored.session.engine.checkInvariants();
    } finally {
      await disk?.close();
      await folder.delete(recursive: true);
    }
  });
}
