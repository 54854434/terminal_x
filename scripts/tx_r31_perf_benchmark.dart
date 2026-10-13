/// R31 repeatable benchmark. Run with Dart/Flutter tooling on a real device
/// (or emulator); results here are NOT measurements in this build environment.
/// Compares the exact same deterministic market with one-shot and persistent
/// worker backends. No network, no actual money or real exchange connection.
import 'dart:io';

import 'package:drift/native.dart';

import '../lib/engine/tx_session.dart';
import '../lib/storage/tx_sqlite_store.dart';
import '../lib/storage/tx_trading_service.dart';

Future<List<int>> sample(bool persistent, int count) async {
  final service = TxTradingService(
    TxSqliteStore(NativeDatabase.memory()),
    initialSessionFactory: TxSession.freshWithAgents,
    persistentMarketWorker: persistent,
  );
  try {
    await service.open();
    final samples = <int>[];
    for (var i = 0; i < count; i++) {
      final sw = Stopwatch()..start();
      await service.nextTick();
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
    }
    service.current.session.engine.checkInvariants();
    return samples;
  } finally {
    await service.close();
  }
}

int percentile(List<int> samples, double p) {
  final values = List<int>.of(samples)..sort();
  final index = ((values.length - 1) * p).ceil();
  return values[index];
}

Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 100 : int.parse(args.first);
  if (count < 10 || count > 5000) {
    throw ArgumentError('Specify 10..5000 committed minutes');
  }
  stdout.writeln('R31 benchmark: $count minutes per backend');
  for (final persistent in [false, true]) {
    final measures = await sample(persistent, count);
    final p50 = percentile(measures, 0.50) / 1000;
    final p95 = percentile(measures, 0.95) / 1000;
    final average = measures.reduce((a, b) => a + b) / measures.length / 1000;
    final theoretical = 60000 / average;
    stdout.writeln('persistent=$persistent '
        'avg=${average.toStringAsFixed(2)}ms '
        'p50=${p50.toStringAsFixed(2)}ms '
        'p95=${p95.toStringAsFixed(2)}ms '
        'capacity=${theoretical.toStringAsFixed(1)}x');
  }
  stdout.writeln('Numbers are machine-specific: do not infer phone speed '
      'from desktop/emulator results. Exact pause and frame timing are separate.');
}
