import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';

void main() {
  late TxSqliteStore store;
  setUp(() => store = TxSqliteStore(NativeDatabase.memory()));
  tearDown(() async => store.close());

  Future<int> count() async => (await store.customSelect(
    'SELECT COUNT(*) AS n FROM snapshots',
  ).getSingle()).read<int>('n');

  test('R25 fast save retains exact canonical account and revision on reopen',
      () async {
    final first = TxSession.fresh();
    final opened = await store.initializeFresh(first);
    var next = TxSession.importJson(opened.session.exportJson())..nextTick();
    final saved = await store.saveSession(next, expectedRevision: 1);
    expect(saved.revision, 2);
    expect(saved.session.exportJson(), next.exportJson());
    next = TxSession.importJson(saved.session.exportJson())..nextTick();
    final later = await store.saveSession(next, expectedRevision: 2);
    expect(later.revision, 3);
    expect((await store.readCurrent())!.session.exportJson(),
        next.exportJson());
    expect((await store.readHistory(limit: 3)).length, 3);
    expect(await count(), 3);
    later.session.engine.checkInvariants();
  });

  test('stale revision is refused without an extra snapshot', () async {
    final first = await store.initializeFresh(TxSession.fresh());
    final next = TxSession.importJson(first.session.exportJson())..nextTick();
    await store.saveSession(next, expectedRevision: 1);
    await expectLater(
      store.saveSession(next, expectedRevision: 1), throwsStateError);
    expect((await store.readCurrent())!.revision, 2);
    expect(await count(), 2);
  });

  test('corrupted prior snapshot checksum blocks fast commit', () async {
    final first = await store.initializeFresh(TxSession.fresh());
    await store.customStatement(
      "UPDATE snapshots SET sha256 = 'CORRUPTED' WHERE revision = 1",
    );
    final candidate = TxSession.importJson(first.session.exportJson())
      ..nextTick();
    await expectLater(store.saveSession(candidate, expectedRevision: 1),
        throwsStateError);
    expect(await count(), 1);
    await expectLater(store.readCurrent(), throwsStateError);
  });

  test('rewritten checksum and invalid ledger cannot evade trusted hash',
      () async {
    final first = await store.initializeFresh(TxSession.fresh());
    final source = jsonDecode(first.session.exportJson())
        as Map<String, dynamic>;
    final engine = jsonDecode(source['engine'] as String)
        as Map<String, dynamic>;
    final accounts = engine['accounts'] as List<dynamic>;
    final player = accounts.first as Map<String, dynamic>;
    player['cashCents'] = (player['cashCents'] as int) + 100;
    source['engine'] = jsonEncode(engine);
    final poisoned = jsonEncode(source);
    final forgedHash = sha256.convert(utf8.encode(poisoned)).toString();
    await store.customStatement('''
      UPDATE snapshots SET payload_json = ?, sha256 = ? WHERE revision = 1
    ''', [poisoned, forgedHash]);
    final candidate = TxSession.importJson(first.session.exportJson())
      ..nextTick();
    await expectLater(store.saveSession(candidate, expectedRevision: 1),
        throwsStateError);
    expect(await count(), 1);
  });

  test('checkpoint failure rolls back the new snapshot and keeps old head',
      () async {
    await store.close();
    var commits = 0;
    store = TxSqliteStore(NativeDatabase.memory(), testCheckpoint: (point) {
      if (point == 'after_session_insert' && ++commits == 2) {
        throw StateError('simulated interruption');
      }
    });
    final original = await store.initializeFresh(TxSession.fresh());
    final candidate = TxSession.importJson(original.session.exportJson())
      ..nextTick();
    await expectLater(store.saveSession(candidate, expectedRevision: 1),
        throwsStateError);
    expect(await count(), 1);
    expect((await store.readCurrent())!.session.exportJson(),
        original.session.exportJson());
    final retry = await store.saveSession(candidate, expectedRevision: 1);
    expect(retry.revision, 2);
    expect(await count(), 2);
  });

  test('an untouched legacy schema-1 snapshot opens and is upgradable',
      () async {
    final first = TxSession.fresh();
    final original = await store.migrateFromPreferencesSnapshot(
        first.exportJson());
    final next = TxSession.importJson(original.session.exportJson())
      ..nextTick();
    final saved = await store.saveSession(next, expectedRevision: 1);
    final reread = (await store.readCurrent())!;
    expect(reread.sha256, saved.sha256);
    expect(reread.session.exportJson(), next.exportJson());
  });

  test('R31 typed candidate validation refuses invalid mutable metadata',
      () async {
    final first = await store.initializeFresh(TxSession.fresh());
    final corrupted = TxSession.importJson(first.session.exportJson());
    corrupted.referenceCents[0] = 0;
    await expectLater(
      store.saveSession(corrupted, expectedRevision: 1), throwsStateError);
    expect((await store.readCurrent())!.revision, 1);
    expect(await count(), 1);
  });

  test('R31 successful full audit is reused during identical typed commit',
      () async {
    final old = await store.initializeFresh(TxSession.fresh());
    final proposed = TxSession.importJson(old.session.exportJson())
      ..nextTick();
    final fullAudits = proposed.engine.fullInvariantAudits;
    expect(fullAudits, greaterThan(0));
    final saved = await store.saveSession(proposed,
        expectedRevision: old.revision);
    // Candidate was completely audited at the end of its market minute.
    // The saving isolate must not need another historical ledger pass.
    expect(saved.session.engine.fullInvariantAudits, fullAudits);
    expect((await store.readCurrent())!.session.exportJson(),
        saved.session.exportJson());
  });
}
