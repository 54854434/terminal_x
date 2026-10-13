import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/storage/tx_sqlite_store.dart';

void main() {
  late TxSqliteStore db;
  setUp(() => db = TxSqliteStore(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('flat committed candle has a neutral direction', () {
    const flat = TxCandle(step: 0, openCents: 1000, highCents: 1000,
        lowCents: 1000, closeCents: 1000, volumeShares: 0);
    expect(flat.rising, isFalse);
    expect(flat.falling, isFalse);
    expect(flat.flat, isTrue);
  });

  test('empty committed history creates zero candles', () async {
    expect(await db.readHistory(), isEmpty);
    expect(TxCandleHistory.fromSnapshots([], 'SIM-A01'), isEmpty);
  });

  test('opening candle reflects first real stored quote, no imaginary volume', () async {
    await db.initializeFresh(TxSession.fresh());
    final bars = TxCandleHistory.fromSnapshots(
        await db.readHistory(), TxSession.symbols[0]);
    expect(bars.length, 1);
    expect(bars.single.step, 0);
    expect(bars.single.openCents, 1000);
    expect(bars.single.highCents, 1000);
    expect(bars.single.lowCents, 1000);
    expect(bars.single.volumeShares, 0);
  });

  test('same-step market buy changes actual candle close and volume', () async {
    final saved = await db.initializeFresh(TxSession.fresh());
    final s = TxSession.importJson(saved.session.exportJson());
    final order = s.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.market, quantity: 2);
    expect(order.filled, 2);
    await db.saveSession(s, expectedRevision: 1);
    final bars = TxCandleHistory.fromSnapshots(
        await db.readHistory(), TxSession.symbols[0]);
    expect(bars.length, 1);
    expect(bars.single.openCents, 1000);
    expect(bars.single.closeCents, 1001);
    expect(bars.single.highCents, 1001);
    expect(bars.single.lowCents, 1000);
    expect(bars.single.volumeShares, 2);
  });

  test('price changes on same step update high/low without new fake bars', () async {
    final first = await db.initializeFresh(TxSession.fresh());
    final a = TxSession.importJson(first.session.exportJson());
    a.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.market, quantity: 101);
    await db.saveSession(a, expectedRevision: 1);
    final b = TxSession.importJson(a.exportJson());
    b.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.sell, kind: TxKind.market, quantity: 1);
    await db.saveSession(b, expectedRevision: 2);
    final c = TxCandleHistory.fromSnapshots(await db.readHistory(), 'SIM-A01');
    expect(c.length, 1);
    expect(c.single.openCents, 1000);
    expect(c.single.highCents, greaterThanOrEqualTo(c.single.closeCents));
    expect(c.single.lowCents, lessThanOrEqualTo(c.single.closeCents));
    expect(c.single.volumeShares, 102);
  });

  test('tick creates next candle even when no new trading happened', () async {
    final first = await db.initializeFresh(TxSession.fresh());
    final s = TxSession.importJson(first.session.exportJson())..nextTick();
    await db.saveSession(s, expectedRevision: 1);
    final candles = TxCandleHistory.fromSnapshots(
        await db.readHistory(), 'SIM-A01');
    expect(candles.map((e) => e.step).toList(), [0, 1]);
    expect(candles[1].volumeShares, 0);
    expect(candles[1].closeCents, s.lastPrice('SIM-A01'));
  });

  test('volume is symbol-specific and no synthetic liquidity is invented', () async {
    final first = await db.initializeFresh(TxSession.fresh());
    final s = TxSession.importJson(first.session.exportJson());
    s.placePlayer(symbol: TxSession.symbols[1],
        side: TxSide.buy, kind: TxKind.market, quantity: 5);
    await db.saveSession(s, expectedRevision: 1);
    final snapshots = await db.readHistory();
    expect(TxCandleHistory.fromSnapshots(snapshots, 'SIM-A01').single.volumeShares, 0);
    expect(TxCandleHistory.fromSnapshots(snapshots, 'SIM-A02').single.volumeShares, 5);
  });

  test('recent history bound does not invent earlier OHLC or fill volume', () async {
    var saved = await db.initializeFresh(TxSession.fresh());
    for (var i = 0; i < 5; i++) {
      final s = TxSession.importJson(saved.session.exportJson())..nextTick();
      saved = await db.saveSession(s, expectedRevision: saved.revision);
    }
    final limited = await db.readHistory(limit: 3);
    expect(limited.map((e) => e.revision).toList(), [4, 5, 6]);
    final bars = TxCandleHistory.fromSnapshots(limited, 'SIM-A01');
    expect(bars.map((e) => e.step).toList(), [3, 4, 5]);
  });

  test('history rejects a tampered checksum and delta head fails closed', () async {
    final first = await db.initializeFresh(TxSession.fresh());
    final s = TxSession.importJson(first.session.exportJson())..nextTick();
    await db.saveSession(s, expectedRevision: 1);
    final row = await db.customSelect(
      'SELECT payload_json FROM snapshots WHERE revision = 2',
    ).getSingle();
    // TXD1 depends on revision 1; TXZ1 is an independent full checkpoint.
    final isDependentDelta = row.read<String>('payload_json').startsWith('TXD1:');
    await db.customStatement("UPDATE snapshots SET sha256 = 'BAD' WHERE revision = 1");
    await expectLater(db.readHistory(), throwsStateError);
    if (isDependentDelta) {
      // Never reconstruct accounts, balances or K-lines from corrupt ancestry.
      await expectLater(db.readCurrent(), throwsStateError);
    } else {
      // A genuine complete checkpoint is independent of an older bad record.
      expect((await db.readCurrent())!.revision, 2);
    }
  });

  test('a complete checkpoint is independently readable but damaged history is not', () async {
    final first = await db.initializeFresh(TxSession.fresh());
    await db.setCheckpointInterval(1);
    final s = TxSession.importJson(first.session.exportJson())..nextTick();
    await db.saveSession(s, expectedRevision: 1);
    final row = await db.customSelect(
      'SELECT payload_json FROM snapshots WHERE revision = 2',
    ).getSingle();
    expect(row.read<String>('payload_json'), startsWith('TXZ1:'));
    await db.customStatement("UPDATE snapshots SET sha256 = 'BAD' WHERE revision = 1");
    await expectLater(db.readHistory(), throwsStateError);
    final restored = await db.readCurrent();
    expect(restored!.revision, 2);
    expect(restored.session.exportJson(), s.exportJson());
  });

  test('history bounds are rejected, not silently relaxed', () async {
    await expectLater(db.readHistory(limit: 0), throwsArgumentError);
    await expectLater(db.readHistory(limit: 501), throwsArgumentError);
  });

  test('candle compiler rejects unsupported symbol and unordered revisions', () async {
    final initial = TxSession.fresh();
    final snapshot = TxStoredSession(session: initial, revision: 1, sha256: 'test');
    expect(() => TxCandleHistory.fromSnapshots([snapshot], 'UNKNOWN'),
        throwsArgumentError);
    expect(() => TxCandleHistory.fromSnapshots([snapshot, snapshot], 'SIM-A01'),
        throwsStateError);
  });

  test('candle compiler rejects reversed simulation steps', () async {
    final initial = TxSession.fresh();
    final later = TxSession.fresh()..nextTick();
    final snapshots = [
      TxStoredSession(session: later, revision: 1, sha256: 'a'),
      TxStoredSession(session: initial, revision: 2, sha256: 'b'),
    ];
    expect(() => TxCandleHistory.fromSnapshots(snapshots, 'SIM-A01'),
        throwsStateError);
  });
}
