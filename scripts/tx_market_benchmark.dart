/// Opt-in long-run baseline; never touches a user database or signs an APK.
/// Run: dart run scripts/tx_market_benchmark.dart [--passive]
/// 100 / 500 / 1000 game minutes, including atomic SQLite save, active NPC
/// matching and audited account snapshot serialization.
import 'dart:io';

import 'package:drift/native.dart';
import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

Future<void> main(List<String> args) async {
  if (args.any((a) => a != '--passive')) {
    throw ArgumentError('Only --passive is supported');
  }
  final passive = args.contains('--passive');
  final folder = await Directory.systemTemp.createTemp('terminal_x_bench_');
  final file = File('${folder.path}/temporary.sqlite');
  TxSqliteStore? database;
  try {
    database = TxSqliteStore(NativeDatabase(file));
    final trader = TxTradingService(database,
        initialSessionFactory: passive
            ? TxSession.fresh : TxSession.freshWithAgents);
    await trader.open();
    final watch = Stopwatch();
    var blockMicros = 0;
    var worstMicros = 0;
    var blockCount = 0;
    stdout.writeln('scenario=${passive ? 'passive' : 'four-funded-NPCs'}; '
        'no limits asserted; all times are environment-dependent');
    for (var minute = 1; minute <= 1000; minute++) {
      watch
        ..reset()
        ..start();
      await trader.nextTick();
      watch.stop();
      final elapsed = watch.elapsedMicroseconds;
      blockMicros += elapsed;
      if (elapsed > worstMicros) worstMicros = elapsed;
      blockCount++;
      if (minute == 100 || minute == 500 || minute == 1000) {
        final bytesRow = await database.customSelect('''
          SELECT COALESCE(SUM(LENGTH(payload_json)), 0) AS bytes
          FROM snapshots
        ''').getSingle();
        final pageCount = await database.customSelect('PRAGMA page_count').getSingle();
        final pageSize = await database.customSelect('PRAGMA page_size').getSingle();
        final dbPages = pageCount.read<int>('page_count');
        final dbPageSize = pageSize.read<int>('page_size');
        final restoreWatch = Stopwatch()..start();
        final current = await database.readCurrent();
        restoreWatch.stop();
        if (current == null || current.session.step != minute) {
          throw StateError('Unexpected restore after $minute minutes');
        }
        current.session.engine.checkInvariants();
        stdout.writeln('minute=$minute, revision=${current.revision}, '
            'avg_commit_ms=${(blockMicros / blockCount / 1000).toStringAsFixed(2)}, '
            'worst_commit_ms=${(worstMicros / 1000).toStringAsFixed(2)}, '
            'restore_ms=${restoreWatch.elapsedMilliseconds}, '
            'sqlite_pages_bytes=${dbPages * dbPageSize}, '
            'snapshot_payload_bytes=${bytesRow.read<int>('bytes')}, '
            'order_count=${current.session.engine.orders.length}, '
            'fill_count=${current.session.engine.fills.length}, '
            'rss_bytes=${ProcessInfo.currentRss}');
        blockMicros = 0;
        worstMicros = 0;
        blockCount = 0;
      }
    }
  } finally {
    await database?.close();
    await folder.delete(recursive: true);
  }
}
