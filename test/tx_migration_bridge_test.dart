import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_migration_bridge.dart';
import '../lib/storage/tx_sqlite_store.dart';

void main() {
  late TxSqliteStore store;

  setUp(() => store = TxSqliteStore(NativeDatabase.memory()));
  tearDown(() async => store.close());

  TxSession sample() {
    final s = TxSession.fresh();
    final buy = s.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.market,
      quantity: 2,
    );
    expect(buy.filled, 2);
    final openBuy = s.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.limit,
      quantity: 5,
      limitPriceCents: 800,
    );
    final openSell = s.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.sell,
      kind: TxKind.limit,
      quantity: 1,
      limitPriceCents: 1500,
    );
    expect(openBuy.status, TxStatus.open);
    expect(openSell.status, TxStatus.open);
    s.engine.checkInvariants();
    return s;
  }

  Future<int> snapshotCount(TxSqliteStore db) async {
    final row = await db.customSelect('SELECT COUNT(*) AS n FROM snapshots').getSingle();
    return row.read<int>('n');
  }

  test('preview is read-only and includes cash, freezes, orders, fills', () async {
    final source = sample();
    final preview = TxMigrationBridge.previewJson(source.exportJson());
    final player = source.engine.account(TxSession.playerId);
    expect(preview.step, 0);
    expect(preview.cashCents, player.cashCents);
    expect(preview.reservedCashCents, 4000);
    expect(preview.shares[TxSession.symbols[0]], 2);
    expect(preview.reservedShares[TxSession.symbols[0]], 1);
    expect(preview.playerOrderCount, 3);
    expect(preview.activePlayerOrderCount, 2);
    expect(preview.playerFillCount, 1);
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
  });

  test('refusing confirmation leaves SQLite untouched', () async {
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    await expectLater(
      TxMigrationBridge.confirmJson(
        store: store, preview: plan, currentSourceJson: raw,
        userConfirmed: false,
      ),
      throwsStateError,
    );
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
  });

  test('confirmed migration preserves the exact session and checksum', () async {
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    final result = await TxMigrationBridge.confirmJson(
      store: store, preview: plan, currentSourceJson: raw,
      userConfirmed: true,
    );
    expect(result.alreadyMigrated, isFalse);
    expect(result.revision, 1);
    expect(result.session.exportJson(), raw);
    expect((await store.readCurrent())!.sha256, plan.sha256);
    expect(await snapshotCount(store), 1);
    result.session.engine.checkInvariants();
  });

  test('valid but changed source after preview is blocked', () async {
    final raw = sample().exportJson();
    final changed = TxSession.importJson(raw)..nextTick();
    final plan = TxMigrationBridge.previewJson(raw);
    await expectLater(
      TxMigrationBridge.confirmJson(
        store: store, preview: plan,
        currentSourceJson: changed.exportJson(), userConfirmed: true,
      ),
      throwsStateError,
    );
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
  });

  test('invalid JSON cannot be previewed or committed', () async {
    expect(() => TxMigrationBridge.previewJson('{broken'), throwsA(anything));
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    await expectLater(
      TxMigrationBridge.confirmJson(
        store: store, preview: plan, currentSourceJson: '{broken',
        userConfirmed: true,
      ),
      throwsA(anything),
    );
    expect(await store.readCurrent(), isNull);
  });

  test('tampered ledger and cash must fail preview', () async {
    final root = jsonDecode(sample().exportJson()) as Map<String, dynamic>;
    final engine = jsonDecode(root['engine'] as String) as Map<String, dynamic>;
    final first = (engine['accounts'] as List).first as Map<String, dynamic>;
    first['cashCents'] = (first['cashCents'] as int) + 123;
    root['engine'] = jsonEncode(engine);
    expect(
      () => TxMigrationBridge.previewJson(jsonEncode(root)),
      throwsA(anything),
    );
    expect(await snapshotCount(store), 0);
  });

  test('second confirmation with identical source never writes again', () async {
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    await TxMigrationBridge.confirmJson(
      store: store, preview: plan, currentSourceJson: raw,
      userConfirmed: true,
    );
    final again = await TxMigrationBridge.confirmJson(
      store: store, preview: plan, currentSourceJson: raw,
      userConfirmed: true,
    );
    expect(again.alreadyMigrated, isTrue);
    expect(again.revision, 1);
    expect(await snapshotCount(store), 1);
  });

  test('repeated migration after trading preserves NEWER SQLite revision', () async {
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    await TxMigrationBridge.confirmJson(
      store: store, preview: plan, currentSourceJson: raw,
      userConfirmed: true,
    );
    final advanced = TxSession.importJson(raw)..nextTick();
    await store.saveSession(advanced, expectedRevision: 1);
    final result = await TxMigrationBridge.confirmJson(
      store: store, preview: plan, currentSourceJson: raw,
      userConfirmed: true,
    );
    expect(result.alreadyMigrated, isTrue);
    expect(result.revision, 2);
    expect(result.session.exportJson(), advanced.exportJson());
    expect(await snapshotCount(store), 2);
  });

  test('different source cannot replace an initialized SQLite account', () async {
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    await TxMigrationBridge.confirmJson(
      store: store, preview: plan, currentSourceJson: raw,
      userConfirmed: true,
    );
    final different = TxSession.importJson(raw)..nextTick();
    final secondPlan = TxMigrationBridge.previewJson(different.exportJson());
    await expectLater(
      TxMigrationBridge.confirmJson(
        store: store, preview: secondPlan,
        currentSourceJson: different.exportJson(), userConfirmed: true,
      ),
      throwsStateError,
    );
    expect((await store.readCurrent())!.session.exportJson(), raw);
    expect(await snapshotCount(store), 1);
  });

  test('simulated crash rolls back migration entirely', () async {
    await store.close();
    store = TxSqliteStore(
      NativeDatabase.memory(),
      testCheckpoint: (p) {
        if (p == 'after_session_insert') throw StateError('simulated crash');
      },
    );
    final raw = sample().exportJson();
    final plan = TxMigrationBridge.previewJson(raw);
    await expectLater(
      TxMigrationBridge.confirmJson(
        store: store, preview: plan, currentSourceJson: raw,
        userConfirmed: true,
      ),
      throwsStateError,
    );
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
    final row = await store.customSelect(
      'SELECT COUNT(*) AS n FROM migration_records',
    ).getSingle();
    expect(row.read<int>('n'), 0);
  });

  test('corrupt existing SQLite data is rejected, never reset', () async {
    final raw = sample().exportJson();
    await store.migrateFromPreferencesSnapshot(raw);
    await store.customStatement(
      "UPDATE snapshots SET sha256 = 'BAD' WHERE revision = 1",
    );
    final plan = TxMigrationBridge.previewJson(raw);
    await expectLater(
      TxMigrationBridge.confirmJson(
        store: store, preview: plan, currentSourceJson: raw,
        userConfirmed: true,
      ),
      throwsStateError,
    );
    expect(await snapshotCount(store), 1);
  });

  test('disk migration survives full database close and re-open', () async {
    final dir = await Directory.systemTemp.createTemp('terminal_x_bridge_');
    final file = File('${dir.path}/bridge.sqlite');
    TxSqliteStore? disk;
    try {
      disk = TxSqliteStore(NativeDatabase(file));
      final raw = sample().exportJson();
      final plan = TxMigrationBridge.previewJson(raw);
      final first = await TxMigrationBridge.confirmJson(
        store: disk, preview: plan, currentSourceJson: raw,
        userConfirmed: true,
      );
      expect(first.revision, 1);
      await disk.close();
      disk = TxSqliteStore(NativeDatabase(file));
      final reopened = await disk.readCurrent();
      expect(reopened!.session.exportJson(), raw);
      expect(reopened.sha256, plan.sha256);
      reopened.session.engine.checkInvariants();
    } finally {
      await disk?.close();
      await dir.delete(recursive: true);
    }
  });
}
