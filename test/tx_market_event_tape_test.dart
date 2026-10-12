import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_market_event_tape.dart';
import '../lib/storage/tx_sqlite_store.dart';

void main() {
  test('real fills, in deterministic sequence, not reference-price ticks', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final before = await db.initializeFresh(TxSession.fresh());
      final candidate = TxSession.importJson(before.session.exportJson());
      final buy = candidate.placePlayer(
        symbol: TxSession.symbols[0], side: TxSide.buy,
        kind: TxKind.market, quantity: 110,
      );
      expect(buy.filled, 110);
      final after = await db.saveSession(candidate,
        expectedRevision: before.revision);
      final tape = TxMinuteEventTape.fromCommits(before, after);
      expect(tape.minute, 0);
      expect(tape.observations.length, greaterThanOrEqualTo(2));
      expect(tape.observations.map((e) => e.ordinal).toList(),
          List.generate(tape.observations.length, (i) => i));
      final acc = TxTradeCandleAccumulator();
      for (final obs in tape.observations) { acc.add(obs); }
      expect(acc.volumeShares, 110);
      expect(acc.highCents, greaterThanOrEqualTo(acc.lowCents!));
      expect(acc.openCents, tape.observations.first.priceCents);
      expect(acc.closeCents, tape.observations.last.priceCents);
      expect(tape.observations.every((e) => e.minute == 0), isTrue);
    } finally { await db.close(); }
  });

  test('market reference movement without fills creates zero trade events', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final before = await db.initializeFresh(TxSession.fresh());
      final candidate = TxSession.importJson(before.session.exportJson())
        ..nextTick();
      final after = await db.saveSession(candidate,
        expectedRevision: before.revision);
      final tape = TxMinuteEventTape.fromCommits(before, after);
      expect(tape.minute, 1);
      expect(tape.observations, isEmpty);
      expect(TxTradeCandleAccumulator().volumeShares, 0);
    } finally { await db.close(); }
  });

  test('replay refuses missing revision, remains read-only', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final a = await db.initializeFresh(TxSession.fresh());
      final bCandidate = TxSession.importJson(a.session.exportJson())
        ..nextTick();
      final b = await db.saveSession(bCandidate, expectedRevision: a.revision);
      final cCandidate = TxSession.importJson(b.session.exportJson())
        ..nextTick();
      final c = await db.saveSession(cCandidate, expectedRevision: b.revision);
      expect(() => TxMinuteEventTape.fromCommits(a, c), throwsStateError);
      final tape = TxMinuteEventTape.fromCommits(b, c);
      expect(tape.observations, isEmpty);
      expect((await db.readCurrent())!.revision, c.revision);
    } finally { await db.close(); }
  });
}
