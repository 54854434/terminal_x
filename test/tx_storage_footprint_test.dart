import '../lib/market/tx_runtime_health.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_storage_footprint.dart';
void main() {
  test('physical size and latest snapshot use different units', () {
    final d = TxStorageFootprint.fromRaw(pageCount: 512, pageSize: 4096,
      snapshotCount: 12, latestSnapshotBytes: 32768, revision: 12);
    expect(d.databaseBytes, 2097152);
    expect(d.databaseMiB, 2.0);
    expect(d.latestSnapshotKiB, 32.0);
    expect(d.largeDatabase, false);
  });
  test('warns over 100MiB physical SQLite size', () {
    final d = TxStorageFootprint.fromRaw(pageCount: 25600, pageSize: 4096,
      snapshotCount: 25, latestSnapshotBytes: 4096, revision: 25);
    expect(d.largeDatabase, true);
  });
  test('invalid sqlite diagnostic values are rejected', () {
    expect(() => TxStorageFootprint.fromRaw(pageCount: -1, pageSize: 4096,
      snapshotCount: 1, latestSnapshotBytes: 100, revision: 1),
      throwsArgumentError);
    expect(() => TxStorageFootprint.fromRaw(pageCount: 1, pageSize: 0,
      snapshotCount: 1, latestSnapshotBytes: 100, revision: 1),
      throwsArgumentError);
    expect(() => TxStorageFootprint.fromRaw(pageCount: 1, pageSize: 4096,
      snapshotCount: 0, latestSnapshotBytes: 0, revision: 1),
      throwsArgumentError);
  });


  test('100x requires approximately 600 ms per committed minute',(){
    final h=TxRuntimeHealth.evaluate(speed:100,sampleCount:12,
      p95Milliseconds:700);
    expect(h.budgetMilliseconds,600);
    expect(h.budgetExceeded,isTrue);
  });
  test('3600x requires 16.7 ms, not a claim of achieved 3600x',(){
    final h=TxRuntimeHealth.evaluate(speed:3600,sampleCount:10,
      p95Milliseconds:30);
    expect(h.budgetMilliseconds,closeTo(16.667,0.01));
    expect(h.budgetExceeded,isTrue);
  });
  test('small sample yields unknown throughput verdict',(){
    final h=TxRuntimeHealth.evaluate(speed:100,sampleCount:4,
      p95Milliseconds:900);
    expect(h.budgetExceeded,isNull);
  });
  test('invalid input rejected',(){
    expect(()=>TxRuntimeHealth.evaluate(speed:0,sampleCount:5,
      p95Milliseconds:10),throwsArgumentError);
  });

}
