import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_delta_codec.dart';

void main() {
  late TxSqliteStore store;
  setUp(() => store = TxSqliteStore(NativeDatabase.memory()));
  tearDown(() async => store.close());

  Future<String> payload(int revision) async {
    final row = await store.customSelect(
      'SELECT payload_json FROM snapshots WHERE revision = ?',
      variables: [Variable.withInt(revision)],
    ).getSingle();
    return row.read<String>('payload_json');
  }

  Future<int> count() async => (await store.customSelect(
    'SELECT COUNT(*) AS n FROM snapshots',
  ).getSingle()).read<int>('n');

  test('R27 reads legacy plaintext and writes version-tagged head',
      () async {
    final start = await store.initializeFresh(TxSession.fresh());
    expect((await payload(1)).startsWith('{'), isTrue);
    final next = TxSession.importJson(start.session.exportJson())..nextTick();
    final committed = await store.saveSession(next, expectedRevision: 1);
    expect(committed.revision, 2);
    expect((await payload(1)).startsWith('{'), isTrue);
    expect((await payload(2)).startsWith('TX'), isTrue);
    expect((await store.readCurrent())!.session.exportJson(), next.exportJson());
  });

  test('revision payload SHA-256 hashes the exact stored TEXT bytes',
      () async {
    final initial = await store.initializeFresh(TxSession.fresh());
    final next = TxSession.importJson(initial.session.exportJson())..nextTick();
    final result = await store.saveSession(next, expectedRevision: 1);
    final compressedText = await payload(2);
    final computed = sha256.convert(utf8.encode(compressedText)).toString();
    expect(result.sha256, computed);
    final rebuilt = (await store.readCurrent())!.session.exportJson();
    expect(rebuilt, next.exportJson());
    if (compressedText.startsWith(TxDeltaCodec.fullPrefix)) {
      expect(TxDeltaCodec.decodeFull(compressedText), next.exportJson());
    }
  });

  test('mixed plaintext, full and delta history keeps committed minutes',
      () async {
    final initial = await store.initializeFresh(TxSession.fresh());
    final one = TxSession.importJson(initial.session.exportJson())..nextTick();
    final rev2 = await store.saveSession(one, expectedRevision: 1);
    final two = TxSession.importJson(rev2.session.exportJson())..nextTick();
    final rev3 = await store.saveSession(two, expectedRevision: 2);
    final history = await store.readHistory(limit: 3);
    expect(history.map((x) => x.revision).toList(), [1, 2, 3]);
    expect(history.first.session.exportJson(), initial.session.exportJson());
    expect(history[1].session.exportJson(), one.exportJson());
    expect(history.last.session.exportJson(), two.exportJson());
    expect(rev3.revision, 3);
    expect(await count(), 3);
  });

  test('revision encoding can reduce the snapshot size',
      () async {
    final initial = await store.initializeFresh(TxSession.fresh());
    final next = TxSession.importJson(initial.session.exportJson())..nextTick();
    await store.saveSession(next, expectedRevision: 1);
    final compressedText = await payload(2);
    expect(compressedText.length, lessThan(next.exportJson().length));
  });

  test('damaged new snapshot bytes fail closed on reopen', () async {
    final initial = await store.initializeFresh(TxSession.fresh());
    final next = TxSession.importJson(initial.session.exportJson())..nextTick();
    await store.saveSession(next, expectedRevision: 1);
    await store.customStatement(
      "UPDATE snapshots SET payload_json = 'TXZ1:BAD', sha256 = 'BAD' "
      'WHERE revision = 2',
    );
    await expectLater(store.readCurrent(), throwsStateError);
    expect(await count(), 2);
  });

  test('forged matching digest of malformed delta fails without reset',
      () async {
    final initial = await store.initializeFresh(TxSession.fresh());
    final next = TxSession.importJson(initial.session.exportJson())..nextTick();
    await store.saveSession(next, expectedRevision: 1);
    const malformed = 'TXD1:bm90LXpsaWI='; // valid Base64, not zlib
    final forgedHash = sha256.convert(utf8.encode(malformed)).toString();
    await store.customStatement('''
      UPDATE snapshots SET payload_json = ?, sha256 = ? WHERE revision = 2
    ''', [malformed, forgedHash]);
    await expectLater(store.readCurrent(), throwsStateError);
    expect(await count(), 2);
  });

  test('frozen cash, holdings and orders survive delta save/reopen',
      () async {
    final before = TxSession.fresh();
    before.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
      kind: TxKind.market, quantity: 10);
    before.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
      kind: TxKind.limit, quantity: 5, limitPriceCents: 800);
    final opened = await store.initializeFresh(before);
    final later = TxSession.importJson(opened.session.exportJson())..nextTick();
    await store.saveSession(later, expectedRevision: 1);
    final restored = (await store.readCurrent())!.session;
    expect(restored.engine.account(TxSession.playerId).reservedCashCents,
      later.engine.account(TxSession.playerId).reservedCashCents);
    expect(restored.playerOrders.length, later.playerOrders.length);
    expect(restored.playerFills.length, later.playerFills.length);
    expect(restored.totalAssetsCents, later.totalAssetsCents);
    restored.engine.checkInvariants();
  });

  test('rollback leaves verified plaintext head intact, retry commits',
      () async {
    await store.close();
    var checkpoints = 0;
    store = TxSqliteStore(NativeDatabase.memory(), testCheckpoint: (point) {
      if (point == 'after_session_insert' && ++checkpoints == 2) {
        throw StateError('interrupted compressed transaction');
      }
    });
    final original = await store.initializeFresh(TxSession.fresh());
    final proposed = TxSession.importJson(original.session.exportJson())
      ..nextTick();
    await expectLater(store.saveSession(proposed, expectedRevision: 1),
      throwsStateError);
    expect(await count(), 1);
    expect((await payload(1)).startsWith('{'), isTrue);
    expect((await store.readCurrent())!.revision, 1);
    final committed = await store.saveSession(proposed, expectedRevision: 1);
    expect(committed.revision, 2);
    expect((await payload(2)).startsWith('TX'), isTrue);
  });

  test('disk persistence supports plaintext and new revision encoding',
      () async {
    final dir = await Directory.systemTemp.createTemp('tx_r26_');
    final file = File('${dir.path}/tx.db');
    TxSqliteStore? disk;
    try {
      disk = TxSqliteStore(NativeDatabase(file));
      final opened = await disk.initializeFresh(TxSession.fresh());
      final next = TxSession.importJson(opened.session.exportJson())
        ..nextTick();
      await disk.saveSession(next, expectedRevision: 1);
      await disk.close();
      disk = TxSqliteStore(NativeDatabase(file));
      final restored = (await disk.readCurrent())!;
      expect(restored.revision, 2);
      expect(restored.session.exportJson(), next.exportJson());
      final history = await disk.readHistory(limit: 2);
      expect(history.length, 2);
      expect(history.first.revision, 1);
      expect(history.last.revision, 2);
    } finally {
      await disk?.close();
      await dir.delete(recursive: true);
    }
  });
}
