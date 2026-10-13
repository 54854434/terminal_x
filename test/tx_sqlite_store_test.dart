import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';

void main() {
  test('R44 market cadence is persisted independently of cash and revisions',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final first = await db.initializeFresh(TxSession.fresh());
      expect(await db.readMarketPulseSeconds(), 15);
      await db.setMarketPulseSeconds(37);
      expect(await db.readMarketPulseSeconds(), 37);
      expect((await db.readCurrent())!.revision, first.revision);
      expect((await db.readCurrent())!.session.exportJson(),
          first.session.exportJson());
      await expectLater(db.setMarketPulseSeconds(4), throwsArgumentError);
      await db.customStatement(
          "UPDATE storage_metadata SET value='INVALID' "
          "WHERE key='market_pulse_seconds_v1'");
      await expectLater(db.readMarketPulseSeconds(), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('automatic save cadence is independent and fail-closed', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final first = await db.initializeFresh(TxSession.fresh());
      expect(await db.readAutomaticSaveMinutes(),
          TxSqliteStore.defaultAutomaticSaveMinutes);
      await db.setAutomaticSaveMinutes(15);
      expect(await db.readAutomaticSaveMinutes(), 15);
      expect((await db.readCurrent())!.revision, first.revision);
      await expectLater(db.setAutomaticSaveMinutes(0), throwsArgumentError);
      await db.customStatement(
          "UPDATE storage_metadata SET value='INVALID' "
          "WHERE key='automatic_save_minutes_v1'");
      await expectLater(db.readAutomaticSaveMinutes(), throwsStateError);
    } finally {
      await db.close();
    }
  });

  late TxSqliteStore store;

  setUp(() => store = TxSqliteStore(NativeDatabase.memory()));
  tearDown(() async => store.close());

  TxSession preparedSession() {
    final session = TxSession.fresh();
    session.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.market,
      quantity: 2,
    );
    session.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.limit,
      quantity: 5,
      limitPriceCents: 800,
    );
    return session;
  }

  Future<int> snapshotCount(TxSqliteStore db) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM snapshots',
    ).getSingle();
    return row.read<int>('n');
  }

  test('fresh database starts EMPTY, never silently creates an account', () async {
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
  });

  test('migration retains cash, holdings, open orders, freezes and fills', () async {
    final input = preparedSession();
    final saved = await store.migrateFromPreferencesSnapshot(input.exportJson());
    expect(saved.revision, 1);
    expect(saved.session.exportJson(), input.exportJson());
    expect(saved.session.playerOrders.length, input.playerOrders.length);
    expect(saved.session.playerFills.length, input.playerFills.length);
    expect(saved.session.engine.account(TxSession.playerId).reservedCashCents,
        4000);
    saved.session.engine.checkInvariants();
    expect(await snapshotCount(store), 1);
  });

  test('identical retry is idempotent, even after new trades', () async {
    final input = preparedSession();
    final raw = input.exportJson();
    await store.migrateFromPreferencesSnapshot(raw);
    final advanced = TxSession.importJson(raw)..nextTick();
    final saved = await store.saveSession(advanced, expectedRevision: 1);
    expect(saved.revision, 2);
    final repeat = await store.migrateFromPreferencesSnapshot(raw);
    expect(repeat.revision, 2);
    expect(repeat.session.exportJson(), advanced.exportJson());
    expect(await snapshotCount(store), 2);
  });

  test('different import source cannot replace an existing account', () async {
    final input = preparedSession();
    await store.migrateFromPreferencesSnapshot(input.exportJson());
    final other = TxSession.fresh()..nextTick();
    await expectLater(
      store.migrateFromPreferencesSnapshot(other.exportJson()),
      throwsStateError,
    );
    expect((await store.readCurrent())!.session.exportJson(),
        input.exportJson());
    expect(await snapshotCount(store), 1);
  });

  test('invalid JSON and tampered ledger fail BEFORE database changes', () async {
    await expectLater(
      store.migrateFromPreferencesSnapshot('{invalid'),
      throwsA(anything),
    );
    final data = jsonDecode(preparedSession().exportJson()) as Map<String, dynamic>;
    final engine = jsonDecode(data['engine'] as String) as Map<String, dynamic>;
    final accounts = engine['accounts'] as List<dynamic>;
    final first = accounts.first as Map<String, dynamic>;
    first['cashCents'] = (first['cashCents'] as int) + 100;
    data['engine'] = jsonEncode(engine);
    await expectLater(
      store.migrateFromPreferencesSnapshot(jsonEncode(data)),
      throwsA(anything),
    );
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
  });

  test('failed initial migration rolls back every table', () async {
    await store.close();
    store = TxSqliteStore(
      NativeDatabase.memory(),
      testCheckpoint: (point) {
        if (point == 'after_session_insert') throw StateError('crash');
      },
    );
    await expectLater(
      store.migrateFromPreferencesSnapshot(preparedSession().exportJson()),
      throwsStateError,
    );
    expect(await store.readCurrent(), isNull);
    expect(await snapshotCount(store), 0);
    final row = await store.customSelect(
      'SELECT COUNT(*) AS n FROM migration_records',
    ).getSingle();
    expect(row.read<int>('n'), 0);
  });

  test('failed save rolls back new snapshot AND active session pointer', () async {
    await store.close();
    var writesAtCheckpoint = 0;
    store = TxSqliteStore(
      NativeDatabase.memory(),
      testCheckpoint: (point) {
        if (point == 'after_session_insert' && ++writesAtCheckpoint == 2) {
          throw StateError('simulated crash before save commit');
        }
      },
    );
    final input = preparedSession();
    await store.migrateFromPreferencesSnapshot(input.exportJson());
    final modified = TxSession.importJson(input.exportJson())..nextTick();
    await expectLater(
      store.saveSession(modified, expectedRevision: 1),
      throwsStateError,
    );
    final stillOriginal = await store.readCurrent();
    expect(stillOriginal!.revision, 1);
    expect(stillOriginal.session.exportJson(), input.exportJson());
    expect(await snapshotCount(store), 1);
  });

  test('failed save at snapshot insertion also rolls back', () async {
    await store.close();
    var snapshotInserts = 0;
    store = TxSqliteStore(
      NativeDatabase.memory(),
      testCheckpoint: (point) {
        if (point == 'after_snapshot_insert' && ++snapshotInserts == 2) {
          throw StateError('simulated interrupted save');
        }
      },
    );
    final input = preparedSession();
    await store.migrateFromPreferencesSnapshot(input.exportJson());
    final modified = TxSession.importJson(input.exportJson())..nextTick();
    await expectLater(
      store.saveSession(modified, expectedRevision: 1),
      throwsStateError,
    );
    expect((await store.readCurrent())!.revision, 1);
    expect(await snapshotCount(store), 1);
  });

  test('reject stale revision without changing the stored snapshot', () async {
    final input = preparedSession();
    await store.migrateFromPreferencesSnapshot(input.exportJson());
    final next = TxSession.importJson(input.exportJson())..nextTick();
    await store.saveSession(next, expectedRevision: 1);
    await expectLater(
      store.saveSession(input, expectedRevision: 1),
      throwsStateError,
    );
    expect((await store.readCurrent())!.session.exportJson(),
        next.exportJson());
    expect(await snapshotCount(store), 2);
  });

  test('checksum mismatch refuses reads without repairing or resetting', () async {
    await store.migrateFromPreferencesSnapshot(preparedSession().exportJson());
    await store.customStatement(
      "UPDATE snapshots SET sha256 = 'BAD' WHERE revision = 1",
    );
    await expectLater(store.readCurrent(), throwsStateError);
    expect(await snapshotCount(store), 1);
  });

  test('real file survives close/reopen, with exact new revision', () async {
    final dir = await Directory.systemTemp.createTemp('terminal_x_sqlite_test_');
    final path = '${dir.path}/storage.sqlite';
    TxSqliteStore? disk;
    try {
      disk = TxSqliteStore(NativeDatabase(File(path)));
      final source = preparedSession();
      await disk.migrateFromPreferencesSnapshot(source.exportJson());
      final next = TxSession.importJson(source.exportJson())..nextTick();
      await disk.saveSession(next, expectedRevision: 1);
      await disk.close();
      disk = TxSqliteStore(NativeDatabase(File(path)));
      final restored = await disk.readCurrent();
      expect(restored!.revision, 2);
      expect(restored.session.exportJson(), next.exportJson());
      restored.session.engine.checkInvariants();
      expect(await snapshotCount(disk), 2);
    } finally {
      await disk?.close();
      await dir.delete(recursive: true);
    }
  });
}
