import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_delta_codec.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';
import '../lib/market/tx_live_candles.dart';

String fixture(int size, {int count = 0, int quantity = 0}) {
  final orders = List.generate(size, (i) => <String, dynamic>{
    'id': 'O$i', 'quantity': i + 2, 'owner': 'NPC', 'status': 'filled',
  });
  if (quantity != 0) orders[4]['quantity'] = quantity;
  for (var i = 0; i < count; i++) {
    orders.add(<String, dynamic>{'id': 'new$i', 'quantity': 1});
  }
  return jsonEncode(<String, dynamic>{
    'schema': 1, 'step': count, 'referenceCents': <int>[1000, 2000],
    'nextPlayerOrder': 1, 'quoteFillStart': 0,
    'archivedLegacyOrders': <dynamic>[],
    'archivedLegacyTrades': <dynamic>[], 'isLegacyUpgrade': false,
    'engine': jsonEncode(<String, dynamic>{
      'version': 1, 'nextOrderSequence': size + count + 1,
      'nextFillSequence': 1,
      'accounts': <dynamic>[], 'orders': orders,
      'fills': <dynamic>[], 'ledger': <dynamic>[],
    }),
  });
}

void main() {
  test('R44 old Rust journal header triggers first full checkpoint', () {
    final newSession = TxSession.importJson(TxSession.fresh().exportJson());
    final canonical = newSession.exportJson();
    final previous = canonical.replaceFirst('"lastPulseSecond":0,', '');
    expect(previous, isNot(canonical));
    final encoded = TxDeltaCodec.encode(
        canonical: canonical, revision: 2, previousRevision: 1,
        previousCanonical: previous,
        previousHash: TxDeltaCodec.checksum(previous),
        trackedSessionHeader: newSession.snapshotHeader(),
        trackedEngineHeader: newSession.engine.snapshotHeader(),
        trackedLists: newSession.engine.snapshotDeltaLists());
    expect(encoded.checkpoint, isTrue);
    expect(TxDeltaCodec.decodeFull(encoded.stored), canonical);
  });

  test('incremental codec replay exactly reconstructs canonical candidate', () {
    final before = fixture(120);
    final after = fixture(120, count: 2, quantity: 99);
    final baseHash = TxDeltaCodec.checksum(before);
    final result = TxDeltaCodec.encode(canonical: after, revision: 3,
      previousRevision: 2, previousCanonical: before, previousHash: baseHash);
    expect(result.checkpoint, isFalse);
    expect(result.stored.startsWith('TXD1:'), isTrue);
    expect(result.stored.length, lessThan(after.length));
    expect(TxDeltaCodec.replay(previousCanonical: before, previousRevision: 2,
      previousHash: baseHash, stored: result.stored), after);
  });

  test('R42 journal delta stores appended Rust events, not entire history', () {
    final session = TxSession.fresh();
    session.nativeEvents.addAll(List<List<Object?>>.generate(1200, (i) =>
        <Object?>[3, 'LP-O-$i', i + 1, 1, 0, 0, 0, 10 + i % 17, 1000]));
    final before = session.exportJson();
    final afterSession = TxSession.importJson(before);
    afterSession.nativeEvents.add(<Object?>[4, 1001, 1]);
    final after = afterSession.exportJson();
    final hash = TxDeltaCodec.checksum(before);
    final patch = TxDeltaCodec.encode(
      canonical: after, revision: 3, previousRevision: 2,
      previousCanonical: before, previousHash: hash,
      trackedSessionHeader: afterSession.snapshotHeader(),
      trackedEngineHeader: afterSession.engine.snapshotHeader(),
      trackedLists: afterSession.engine.snapshotDeltaLists(),
      trackedNativeJournal: afterSession.snapshotNativeJournalDelta(),
    );
    expect(patch.checkpoint, isFalse);
    expect(patch.stored.startsWith('TXD1:'), isTrue);
    expect(patch.stored.length * 8, lessThan(after.length));
    expect(TxDeltaCodec.replay(previousCanonical: before,
      previousRevision: 2, previousHash: hash, stored: patch.stored), after);

    final raw = jsonDecode(utf8.decode(ZLibCodec().decode(
      base64Decode(patch.stored.substring(TxDeltaCodec.deltaPrefix.length)))))
        as Map<String, dynamic>;
    expect(raw['version'], 2);
    expect((raw['session'] as Map).containsKey('nativeEvents'), isFalse);
    expect((raw['nativeJournal'] as Map)['oldLength'], 1200);
    expect((raw['nativeJournal'] as Map)['append'], <dynamic>[
      <dynamic>[4, 1001, 1],
    ]);
    (raw['nativeJournal'] as Map)['oldLength'] = 1199;
    final altered = '${TxDeltaCodec.deltaPrefix}${base64Encode(
      ZLibCodec(level: 1).encode(utf8.encode(jsonEncode(raw))))}';
    expect(() => TxDeltaCodec.replay(previousCanonical: before,
      previousRevision: 2, previousHash: hash, stored: altered),
      throwsStateError);
    // Full canonical JSON is unaffected; reopening resets only the cursor.
    expect(TxSession.importJson(after).exportJson(), after);
  });

  test('R42 SQLite saves and reopens append-only Rust journal revisions',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final session = TxSession.fresh();
      session.nativeEvents.addAll(List<List<Object?>>.generate(240, (i) =>
          <Object?>[3, 'SIM-ORDER-$i', i + 1, 1, 0, 0, 0, 1, 1000]));
      final initial = await store.initializeFresh(session);
      final proposed = TxSession.importJson(initial.session.exportJson());
      proposed.nativeEvents.add(<Object?>[4, 200, 1]);
      final saved = await store.saveSession(proposed,
          expectedRevision: initial.revision);
      expect(saved.revision, 2);
      final row = await store.customSelect('''
        SELECT payload_json FROM snapshots WHERE revision = 2
      ''').getSingle();
      expect(row.read<String>('payload_json').startsWith('TXD1:'), isTrue);
      final current = (await store.readCurrent())!;
      expect(current.session.exportJson(), proposed.exportJson());
      expect(current.session.nativeEvents.length, 241);
      final next = TxSession.importJson(current.session.exportJson());
      next.nativeEvents.add(<Object?>[4, 201, 1]);
      final later = await store.saveSession(next, expectedRevision: 2);
      expect(later.revision, 3);
      expect((await store.readCurrent())!.session.exportJson(),
          next.exportJson());
      expect((await store.readHistory(limit: 3)).length, 3);
    } finally {
      await store.close();
    }
  });

  test('R42 tampered committed journal refuses an incremental save',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final session = TxSession.fresh();
      session.nativeEvents.addAll(List<List<Object?>>.generate(240, (i) =>
          <Object?>[3, 'ORDER-$i', i + 1, 1, 0, 0, 0, 1, 1000]));
      final initial = await store.initializeFresh(session);
      final forged = TxSession.importJson(initial.session.exportJson());
      forged.nativeEvents.first[1] = 'CHANGED-OLD-COMMAND';
      await expectLater(store.saveSession(forged,
          expectedRevision: initial.revision), throwsStateError);
      final saved = (await store.readCurrent())!;
      expect(saved.revision, 1);
      expect(saved.session.exportJson(), initial.session.exportJson());
    } finally {
      await store.close();
    }
  });

  test('delta chain rejects a wrong revision and a wrong base digest', () {
    final before = fixture(120);
    final after = fixture(120, count: 1);
    final digest = TxDeltaCodec.checksum(before);
    final data = TxDeltaCodec.encode(canonical: after, revision: 5,
      previousRevision: 4, previousCanonical: before, previousHash: digest);
    expect(data.checkpoint, isFalse);
    expect(() => TxDeltaCodec.replay(previousCanonical: before,
        previousRevision: 3, previousHash: digest, stored: data.stored),
      throwsStateError);
    expect(() => TxDeltaCodec.replay(previousCanonical: before,
        previousRevision: 4, previousHash: 'incorrect', stored: data.stored),
      throwsStateError);
  });

  test('every 32nd revision is a complete recovery checkpoint', () {
    final before = fixture(120);
    final after = fixture(120, count: 1);
    final result = TxDeltaCodec.encode(canonical: after, revision: 32,
      previousRevision: 31, previousCanonical: before,
      previousHash: TxDeltaCodec.checksum(before));
    expect(result.checkpoint, isTrue);
    expect(result.stored.startsWith('TXZ1:'), isTrue);
    expect(TxDeltaCodec.decodeFull(result.stored), after);
  });

  test('when delta is inefficient, codec safely falls back to full checkpoint', () {
    final before = fixture(4);
    final after = fixture(4, count: 120);
    final result = TxDeltaCodec.encode(canonical: after, revision: 3,
      previousRevision: 2, previousCanonical: before,
      previousHash: TxDeltaCodec.checksum(before));
    expect(result.checkpoint, isTrue);
    expect(TxDeltaCodec.decodeFull(result.stored), after);
  });

  test('full decoder accepts old plaintext and rejects unanchored delta', () {
    final plaintext = fixture(12);
    expect(TxDeltaCodec.decodeFull(plaintext), plaintext);
    expect(() => TxDeltaCodec.decodeFull('TXD1:bm90LXpsaWI='),
      throwsStateError);
    expect(() => TxDeltaCodec.decodeFull('TXZ1:bm90LXpsaWI='),
      throwsStateError);
  });

  test('store restores deltas after reopening and history remains ordered',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final first = await store.initializeFresh(TxSession.fresh());
      var current = first;
      for (var i = 0; i < 7; i++) {
        final candidate = TxSession.importJson(current.session.exportJson())
          ..nextTick();
        current = await store.saveSession(candidate,
          expectedRevision: current.revision);
        expect((await store.readCurrent())!.session.exportJson(),
          candidate.exportJson());
      }
      final history = await store.readHistory(limit: 4);
      expect(history.map((e) => e.revision).toList(), <int>[5, 6, 7, 8]);
      expect(history.last.session.exportJson(), current.session.exportJson());
    } finally {
      await store.close();
    }
  });

  test('failed incremental write leaves original head and no extra row',
      () async {
    var writes = 0;
    final store = TxSqliteStore(NativeDatabase.memory(),
      testCheckpoint: (point) {
        if (point == 'after_session_insert' && ++writes == 3) {
          throw StateError('crash before delta commit');
        }
      });
    try {
      final initial = await store.initializeFresh(TxSession.fresh());
      final step2 = TxSession.importJson(initial.session.exportJson())..nextTick();
      final saved2 = await store.saveSession(step2, expectedRevision: 1);
      final step3 = TxSession.importJson(saved2.session.exportJson())..nextTick();
      await expectLater(store.saveSession(step3, expectedRevision: 2),
        throwsStateError);
      final restored = (await store.readCurrent())!;
      expect(restored.revision, 2);
      expect(restored.session.exportJson(), step2.exportJson());
      final rows = (await store.customSelect('SELECT COUNT(*) AS n FROM snapshots')
        .getSingle()).read<int>('n');
      expect(rows, 2);
    } finally {
      await store.close();
    }
  });

  test('delta tampering invalidates head even with forged matching digest',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final opened = await store.initializeFresh(TxSession.fresh());
      final next = TxSession.importJson(opened.session.exportJson())..nextTick();
      final saved = await store.saveSession(next, expectedRevision: 1);
      const forged = 'TXD1:bm90LXpsaWI=';
      await store.customStatement('''
        UPDATE snapshots SET payload_json = ?, sha256 = ? WHERE revision = 2
      ''', <Object?>[forged, TxDeltaCodec.checksum(forged)]);
      await expectLater(store.readCurrent(), throwsStateError);
      final attempted = TxSession.importJson(saved.session.exportJson())..nextTick();
      await expectLater(store.saveSession(attempted, expectedRevision: 2),
        throwsStateError);
    } finally {
      await store.close();
    }
  });

  test('frozen balances and orders survive bounded incremental chain',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final first = TxSession.fresh();
      first.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
        kind: TxKind.market, quantity: 5);
      first.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
        kind: TxKind.limit, quantity: 5, limitPriceCents: 800);
      var saved = await store.initializeFresh(first);
      for (var i = 0; i < 5; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await store.saveSession(next, expectedRevision: saved.revision);
      }
      final restored = (await store.readCurrent())!.session;
      expect(restored.engine.account(TxSession.playerId).reservedCashCents,
        saved.session.engine.account(TxSession.playerId).reservedCashCents);
      expect(restored.engine.account(TxSession.playerId).sharesOf(TxSession.symbols[0]),
        saved.session.engine.account(TxSession.playerId).sharesOf(TxSession.symbols[0]));
      restored.engine.checkInvariants();
    } finally {
      await store.close();
    }
  });

  test('real store writes a full checkpoint at revision 32', () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      var saved = await store.initializeFresh(TxSession.fresh());
      for (var i = 1; i < TxDeltaCodec.checkpointInterval; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await store.saveSession(next, expectedRevision: saved.revision);
      }
      expect(saved.revision, 32);
      final row = await store.customSelect('''
        SELECT payload_json FROM snapshots WHERE revision = 32
      ''').getSingle();
      expect(row.read<String>('payload_json').startsWith('TXZ1:'), isTrue);
      final actual = (await store.readCurrent())!;
      expect(actual.session.exportJson(), saved.session.exportJson());
      final slice = await store.readHistory(limit: 4);
      expect(slice.map((e) => e.revision).toList(), <int>[29, 30, 31, 32]);
    } finally {
      await store.close();
    }
  });

  test('missing immediate predecessor of a delta head fails closed',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      var saved = await store.initializeFresh(TxSession.fresh());
      var latestIsDelta = false;
      // Full checkpoints may occur early; require an actual delta head first.
      for (var i = 0; i < 16; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await store.saveSession(next, expectedRevision: saved.revision);
        final row = await store.customSelect('''
          SELECT payload_json FROM snapshots WHERE revision = ?
        ''', variables: [Variable.withInt(saved.revision)]).getSingle();
        latestIsDelta = row.read<String>('payload_json').startsWith('TXD1:');
        if (latestIsDelta) break;
      }
      expect(latestIsDelta, isTrue);
      // Removing a parent of the active delta must reject recovery.
      await store.customStatement('''
        DELETE FROM snapshots WHERE revision = ?
      ''', <Object?>[saved.revision - 1]);
      await expectLater(store.readCurrent(), throwsStateError);
    } finally {
      await store.close();
    }
  });

  test('disk reopen across deltas is byte-for-byte faithful', () async {
    final dir = await Directory.systemTemp.createTemp('tx_r27_');
    final file = File('${dir.path}/terminal.db');
    TxSqliteStore? disk;
    try {
      disk = TxSqliteStore(NativeDatabase(file));
      var saved = await disk.initializeFresh(TxSession.fresh());
      for (var i = 0; i < 5; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await disk.saveSession(next, expectedRevision: saved.revision);
      }
      await disk.close();
      disk = null;
      disk = TxSqliteStore(NativeDatabase(file));
      final reopened = (await disk.readCurrent())!;
      expect(reopened.session.exportJson(), saved.session.exportJson());
      final history = await disk.readHistory(limit: 6);
      expect(history.length, 6);
      expect(history.last.sha256, reopened.sha256);
    } finally {
      await disk?.close();
      await dir.delete(recursive: true);
    }
  });


  test('checkpoint policy validates bounds and defaults to original 32', () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      expect(await store.readCheckpointInterval(), 32);
      await expectLater(store.setCheckpointInterval(0), throwsArgumentError);
      await expectLater(store.setCheckpointInterval(65), throwsArgumentError);
      await expectLater(store.setCheckpointInterval(4), throwsStateError);
      expect(await store.readCheckpointInterval(), 32);
    } finally {
      await store.close();
    }
  });

  test('custom four-commit checkpoint persists without changing player revision',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      var saved = await store.initializeFresh(TxSession.fresh());
      final originalJson = saved.session.exportJson();
      final originalSha = saved.sha256;
      await store.setCheckpointInterval(4);
      expect(await store.readCheckpointInterval(), 4);
      final same = (await store.readCurrent())!;
      expect(same.revision, 1);
      expect(same.sha256, originalSha);
      expect(same.session.exportJson(), originalJson);
      for (var i = 0; i < 3; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await store.saveSession(next,
          expectedRevision: saved.revision);
      }
      expect(saved.revision, 4);
      final row = await store.customSelect(
        'SELECT payload_json FROM snapshots WHERE revision = 4').getSingle();
      expect(row.read<String>('payload_json').startsWith('TXZ1:'), isTrue);
      expect((await store.readCurrent())!.session.exportJson(),
        saved.session.exportJson());
    } finally {
      await store.close();
    }
  });

  test('switching from short to long cadence preserves history and freezes',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final initial = TxSession.fresh();
      initial.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
        kind: TxKind.limit, quantity: 3, limitPriceCents: 800);
      var saved = await store.initializeFresh(initial);
      await store.setCheckpointInterval(4);
      for (var i = 0; i < 3; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await store.saveSession(next,
          expectedRevision: saved.revision);
      }
      await store.setCheckpointInterval(8);
      expect(await store.readCheckpointInterval(), 8);
      for (var i = 0; i < 4; i++) {
        final next = TxSession.importJson(saved.session.exportJson())..nextTick();
        saved = await store.saveSession(next,
          expectedRevision: saved.revision);
      }
      final row = await store.customSelect(
        'SELECT payload_json FROM snapshots WHERE revision = 8').getSingle();
      expect(row.read<String>('payload_json').startsWith('TXZ1:'), isTrue);
      expect((await store.readHistory(limit: 7)).length, 7);
      final restored = (await store.readCurrent())!.session;
      expect(restored.exportJson(), saved.session.exportJson());
      expect(restored.engine.account(TxSession.playerId).reservedCashCents,
        saved.session.engine.account(TxSession.playerId).reservedCashCents);
    } finally {
      await store.close();
    }
  });

  test('metadata cadence survives disk reopen and unchanged session hash',
      () async {
    final dir = await Directory.systemTemp.createTemp('tx_r28_policy_');
    final file = File('${dir.path}/terminal.db');
    TxSqliteStore? disk;
    try {
      disk = TxSqliteStore(NativeDatabase(file));
      final original = await disk.initializeFresh(TxSession.fresh());
      await disk.setCheckpointInterval(17);
      await disk.close();
      disk = null;
      disk = TxSqliteStore(NativeDatabase(file));
      expect(await disk.readCheckpointInterval(), 17);
      final after = (await disk.readCurrent())!;
      expect(after.sha256, original.sha256);
      expect(after.revision, original.revision);
      expect(after.session.exportJson(), original.session.exportJson());
    } finally {
      await disk?.close();
      await dir.delete(recursive: true);
    }
  });

  test('invalid policy metadata is not silently replaced', () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      var saved = await store.initializeFresh(TxSession.fresh());
      await store.customStatement('''
        INSERT INTO storage_metadata(key, value)
        VALUES ('checkpoint_interval', '500')
      ''');
      await expectLater(store.readCheckpointInterval(), throwsStateError);
      final next = TxSession.importJson(saved.session.exportJson())..nextTick();
      await expectLater(store.saveSession(next, expectedRevision: saved.revision),
        throwsStateError);
      expect((await store.readCurrent())!.revision, 1);
    } finally {
      await store.close();
    }
  });

  test('codec uses custom interval and universal revision-64 safety cap', () {
    final before = fixture(120);
    final after = fixture(120, count: 1);
    final hash = TxDeltaCodec.checksum(before);
    final atFour = TxDeltaCodec.encode(canonical: after, revision: 4,
      previousRevision: 3, previousCanonical: before,
      previousHash: hash, checkpointInterval: 4);
    expect(atFour.checkpoint, isTrue);
    final at64 = TxDeltaCodec.encode(canonical: after, revision: 64,
      previousRevision: 63, previousCanonical: before,
      previousHash: hash, checkpointInterval: 63);
    expect(at64.checkpoint, isTrue);
    expect(() => TxDeltaCodec.encode(canonical: after, revision: 4,
      previousRevision: 3, previousCanonical: before,
      previousHash: hash, checkpointInterval: 0), throwsArgumentError);
  });


  test('mutation journal emits only changed historical order and appended records', () {
    final session = TxSession.importJson(TxSession.fresh().exportJson());
    final e = session.engine;
    final oldOrders = e.orders.length;
    final oldFills = e.fillCount;
    final oldLedger = e.ledger.length;
    session.nextTick();
    final journal = e.snapshotDeltaLists()!;
    final orders = Map<String, dynamic>.from(journal['orders'] as Map);
    final fills = Map<String, dynamic>.from(journal['fills'] as Map);
    final ledger = Map<String, dynamic>.from(journal['ledger'] as Map);
    expect(orders['oldLength'], oldOrders);
    expect((orders['append'] as List).length, e.orders.length - oldOrders);
    expect(fills['oldLength'], oldFills);
    expect((fills['append'] as List).length, e.fillCount - oldFills);
    expect(ledger['oldLength'], oldLedger);
    expect((ledger['append'] as List).length, e.ledger.length - oldLedger);
  });

  test('journal delta roundtrips exactly after NPC tick', () {
    final first = TxSession.importJson(TxSession.fresh().exportJson());
    final before = first.exportJson();
    final oldHash = TxDeltaCodec.checksum(before);
    first.nextTick();
    final after = first.exportJson();
    final encoded = TxDeltaCodec.encode(canonical: after, revision: 2,
      previousRevision: 1, previousCanonical: before, previousHash: oldHash,
      trackedSessionHeader: first.snapshotHeader(),
      trackedEngineHeader: first.engine.snapshotHeader(),
      trackedLists: first.engine.snapshotDeltaLists());
    if (encoded.checkpoint) {
      expect(TxDeltaCodec.decodeFull(encoded.stored), after);
    } else {
      expect(TxDeltaCodec.replay(previousCanonical: before,
        previousRevision: 1, previousHash: oldHash, stored: encoded.stored), after);
    }
  });

  test('journal tracks player order reserve and cancellation faithfully', () {
    final s = TxSession.importJson(TxSession.fresh().exportJson());
    final before = s.exportJson();
    final oldHash = TxDeltaCodec.checksum(before);
    final placed = s.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
      kind: TxKind.limit, quantity: 3, limitPriceCents: 700);
    s.cancelPlayer(placed.id);
    final after = s.exportJson();
    final delta = TxDeltaCodec.encode(canonical: after, revision: 2,
      previousRevision: 1, previousCanonical: before, previousHash: oldHash,
      trackedSessionHeader: s.snapshotHeader(),
      trackedEngineHeader: s.engine.snapshotHeader(),
      trackedLists: s.engine.snapshotDeltaLists());
    if (delta.checkpoint) {
      expect(TxDeltaCodec.decodeFull(delta.stored), after);
    } else {
      expect(TxDeltaCodec.replay(previousCanonical: before,
        previousRevision: 1, previousHash: oldHash, stored: delta.stored), after);
    }
    s.engine.checkInvariants();
  });

  test('journal resets only after snapshot import', () {
    final s = TxSession.importJson(TxSession.fresh().exportJson());
    s.nextTick();
    final prior = s.engine.snapshotDeltaLists()!;
    expect((prior['orders'] as Map)['append'], isNotEmpty);
    final restored = TxSession.importJson(s.exportJson());
    final after = restored.engine.snapshotDeltaLists()!;
    expect((after['orders'] as Map)['append'], isEmpty);
    expect((after['fills'] as Map)['append'], isEmpty);
    expect((after['ledger'] as Map)['append'], isEmpty);
    restored.engine.checkInvariants();
  });

  test('journal replacement count is bounded despite old order history', () {
    final s = TxSession.importJson(TxSession.fresh().exportJson());
    for (var i = 0; i < 15; i++) {
      // Starting a minute cancels existing LP liquidity and appends new orders.
      s.nextTick();
    }
    final newBase = TxSession.importJson(s.exportJson());
    final oldOrderCount = newBase.engine.orders.length;
    newBase.nextTick();
    final changes = newBase.engine.snapshotDeltaLists()!;
    final oldUpdates = ((changes['orders'] as Map)['updates'] as List);
    expect(oldOrderCount, greaterThan(100));
    expect(oldUpdates.length, lessThan(oldOrderCount ~/ 2));
  });

  test('minute batch performs complete final validation and preserves replay', () {
    final s = TxSession.importJson(TxSession.fresh().exportJson());
    final base = s.exportJson();
    s.nextTick();
    s.engine.checkInvariants();
    final encoded = TxDeltaCodec.encode(canonical: s.exportJson(),
      revision: 2, previousRevision: 1, previousCanonical: base,
      previousHash: TxDeltaCodec.checksum(base),
      trackedSessionHeader: s.snapshotHeader(),
      trackedEngineHeader: s.engine.snapshotHeader(),
      trackedLists: s.engine.snapshotDeltaLists());
    expect(encoded.checkpoint || TxDeltaCodec.replay(
      previousCanonical: base, previousRevision: 1,
      previousHash: TxDeltaCodec.checksum(base),
      stored: encoded.stored) == s.exportJson(), isTrue);
  });

  test('R31 persistent market worker matches legacy deterministic trading',
      () async {
    final baseline = TxTradingService(TxSqliteStore(NativeDatabase.memory()),
      initialSessionFactory: TxSession.freshWithAgents);
    final optimized = TxTradingService(TxSqliteStore(NativeDatabase.memory()),
      initialSessionFactory: TxSession.freshWithAgents,
      persistentMarketWorker: true);
    try {
      final a = await baseline.open();
      final b = await optimized.open();
      expect(b.session.exportJson(), a.session.exportJson());
      for (var i = 0; i < 4; i++) {
        final original = await baseline.nextTick();
        final updated = await optimized.nextTick();
        expect(updated.revision, original.revision);
        expect(updated.session.exportJson(), original.session.exportJson());
        updated.session.engine.checkInvariants();
      }
    } finally {
      await baseline.close();
      await optimized.close();
    }
  });

  test('R31 persistent worker invalid cancel safely resynchronizes', () async {
    final service = TxTradingService(TxSqliteStore(NativeDatabase.memory()),
      persistentMarketWorker: true);
    try {
      final first = await service.open();
      await expectLater(service.cancel('DOES_NOT_EXIST'), throwsStateError);
      expect(service.blocked, isFalse);
      expect(service.current.revision, first.revision);
      final after = await service.nextTick();
      expect(after.revision, first.revision + 1);
      after.session.engine.checkInvariants();
    } finally {
      await service.close();
    }
  });

  test('R31 persistent worker keeps frozen funds and cancel in sync', () async {
    final service = TxTradingService(TxSqliteStore(NativeDatabase.memory()),
      persistentMarketWorker: true);
    try {
      await service.open();
      final placed = await service.place(
        symbol: TxSession.symbols.first, side: TxSide.buy,
        kind: TxKind.limit, quantity: 2, limitPriceCents: 600);
      expect(placed.status, TxStatus.open);
      expect(service.current.session.engine.account(TxSession.playerId)
          .reservedCashCents, 1200);
      await service.cancel(placed.id);
      expect(service.current.session.engine.account(TxSession.playerId)
          .reservedCashCents, 0);
      expect(service.current.revision, 3);
      expect((await service.database.readCurrent())!.session.exportJson(),
          service.current.session.exportJson());
    } finally {
      await service.close();
    }
  });

  test('R31 cached OHLC read model follows a committed revision', () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final initial = await store.initializeFresh(TxSession.fresh());
      final recent = await store.readHistory(limit: 64);
      final original = TxLiveCandles.fromVerifiedHistory(recent);
      expect(await store.readCandleIndex(initial), isNull);
      await store.seedCandleIndex(initial, original);
      final index = await store.readCandleIndex(initial);
      expect(index, isNotNull);
      expect(index!.forSymbol(TxSession.symbols.first).last.closeCents,
          original.forSymbol(TxSession.symbols.first).last.closeCents);
      final next = TxSession.importJson(initial.session.exportJson())
        ..nextTick();
      final saved = await store.saveSession(next,
          expectedRevision: initial.revision);
      final loaded = await store.readCandleIndex(saved);
      expect(loaded, isNotNull);
      expect(loaded!.forSymbol(TxSession.symbols.first).last.step,
          saved.session.step);
      expect(loaded!.forSymbol(TxSession.symbols.first).last.closeCents,
          saved.session.lastPrice(TxSession.symbols.first));
      expect(saved.revision, 2);
    } finally {
      await store.close();
    }
  });

  test('R31 damaged read model falls back without touching real ledger',
      () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final initial = await store.initializeFresh(TxSession.fresh());
      await store.seedCandleIndex(initial,
          TxLiveCandles.fromVerifiedHistory(
              await store.readHistory(limit: 64)));
      await store.customStatement('''
        UPDATE storage_metadata SET value = 'BAD' WHERE key = 'candle_index_v1'
      ''');
      expect(await store.readCandleIndex(initial), isNull);
      expect((await store.readHistory(limit: 1)).single.revision, 1);
      expect((await store.readCurrent())!.session.exportJson(),
          initial.session.exportJson());
    } finally {
      await store.close();
    }
  });

  test('R31 candle cache rejects an obsolete revision head', () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      final initial = await store.initializeFresh(TxSession.fresh());
      await store.seedCandleIndex(initial,
        TxLiveCandles.fromVerifiedHistory(
          await store.readHistory(limit: 64)));
      final next = TxSession.importJson(initial.session.exportJson())
        ..nextTick();
      final saved = await store.saveSession(next,
          expectedRevision: initial.revision);
      final older = await store.readCandleIndex(initial);
      expect(older, isNull);
      expect(await store.readCandleIndex(saved), isNotNull);
    } finally {
      await store.close();
    }
  });

  test('R34 off-thread cold restore still fails closed on a damaged head', () async {
    final store = TxSqliteStore(NativeDatabase.memory());
    try {
      var saved = await store.initializeFresh(TxSession.freshWithAgents());
      for (var i = 0; i < 3; i++) {
        final next = TxSession.importJson(saved.session.exportJson())
          ..nextTick();
        saved = await store.saveSession(next, expectedRevision: saved.revision);
      }
      final intact = await store.readCurrent();
      expect(intact!.revision, saved.revision);
      expect(intact.session.step, 3);
      await store.customStatement(
        "UPDATE snapshots SET sha256 = 'BAD' WHERE revision = ?",
        [saved.revision]);
      await expectLater(store.readCurrent(), throwsStateError);
    } finally {
      await store.close();
    }
  });
}
