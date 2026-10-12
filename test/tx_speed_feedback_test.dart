import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_speed_feedback.dart';

void main() {
  test('chart frame budget scales past 100x without losing minute records', () {
    final policy = TxSpeedViewPolicy.suggestMinutes;
    expect(policy(requestedSpeed: 100, refreshRateHz: 60), 1);
    expect(policy(requestedSpeed: 120, refreshRateHz: 60), 1);
    expect(policy(requestedSpeed: 600, refreshRateHz: 60), 5);
    expect(policy(requestedSpeed: 3600, refreshRateHz: 60), 15);
    expect(policy(requestedSpeed: 36000, refreshRateHz: 60), 240);
    expect(policy(requestedSpeed: 360000, refreshRateHz: 60), 1440);
    expect(policy(requestedSpeed: 600, refreshRateHz: 120), 1);
    expect(TxSpeedViewPolicy.estimatedFramesPerBar(
        requestedSpeed: 100, refreshRateHz: 60, periodMinutes: 1), 36);
    expect(TxSpeedViewPolicy.additionalSampleStride(
        requestedSpeed: 1000000, refreshRateHz: 60), greaterThan(1));
    expect(() => policy(requestedSpeed: 0, refreshRateHz: 60),
        throwsArgumentError);
  });

  test('verified throughput ignores speculative demand and bounds memory', () {
    final window = TxCommittedSpeedWindow(capacity: 4);
    window.record(elapsedMilliseconds: 0, minute: 100);
    expect(window.achievedMultiplier, 0);
    window.record(elapsedMilliseconds: 1000, minute: 102);
    expect(window.achievedMultiplier, 120);
    window.record(elapsedMilliseconds: 2000, minute: 102);
    expect(window.achievedMultiplier, 60);
    window.record(elapsedMilliseconds: 3000, minute: 108);
    window.record(elapsedMilliseconds: 4000, minute: 110);
    expect(window.sampleCount, 4);
    expect(window.achievedMultiplier, closeTo(160, 0.001));
    expect(() => window.record(elapsedMilliseconds: 3900, minute: 111),
        throwsStateError);
    window.reset();
    expect(window.achievedMultiplier, 0);
  });

  test('pause during compute discards stale proposal synchronously', () {
    final gate = TxSingleFlightBatchGate()..resume();
    final token = gate.beginCompute()!;
    expect(gate.beginCompute(), isNull);
    gate.pause();
    expect(gate.playing, isFalse);
    expect(gate.beginAtomicWrite(token), isFalse);
    expect(gate.phase, TxBatchPhase.idle);
    gate.resume();
    final newToken = gate.beginCompute()!;
    gate.speedChanged();
    expect(gate.beginAtomicWrite(newToken), isFalse);
  });

  test('pause during in-flight SQLite transaction leaves commit safe', () {
    final gate = TxSingleFlightBatchGate()..resume();
    final token = gate.beginCompute()!;
    expect(gate.beginAtomicWrite(token), isTrue);
    gate.pause();
    expect(gate.beginCompute(), isNull);
    expect(gate.finishAtomicWrite(token), isFalse);
    expect(gate.playing, isFalse);
    gate.resume();
    expect(gate.beginCompute(), isNotNull);
  });

  test('ambiguous commit is fail-closed', () {
    final gate = TxSingleFlightBatchGate()..resume();
    final token = gate.beginCompute()!;
    expect(gate.beginAtomicWrite(token), isTrue);
    gate.storageFailed();
    expect(gate.beginCompute(), isNull);
    expect(() => gate.resume(), throwsStateError);
    expect(() => gate.finishAtomicWrite(token), throwsStateError);
  });
  test('resume is blocked until paused in-flight write reconciles', () {
    final gate = TxSingleFlightBatchGate()..resume();
    final token = gate.beginCompute()!;
    expect(gate.beginAtomicWrite(token), isTrue);
    gate.pause();
    expect(() => gate.resume(), throwsStateError);
    expect(gate.playing, isFalse);
    expect(gate.finishAtomicWrite(token), isFalse);
    gate.resume();
    expect(gate.beginCompute(), isNotNull);
  });

  test('resume is blocked until a stale compute is discarded', () {
    final gate = TxSingleFlightBatchGate()..resume();
    final token = gate.beginCompute()!;
    gate.pause();
    expect(() => gate.resume(), throwsStateError);
    expect(gate.beginAtomicWrite(token), isFalse);
    gate.resume();
    expect(gate.beginCompute(), isNotNull);
  });

  test('speed change rejected while an atomic write is in flight', () {
    final gate = TxSingleFlightBatchGate()..resume();
    final token = gate.beginCompute()!;
    expect(gate.beginAtomicWrite(token), isTrue);
    expect(() => gate.speedChanged(), throwsStateError);
    expect(gate.finishAtomicWrite(token), isTrue);
    gate.speedChanged();
  });

}
