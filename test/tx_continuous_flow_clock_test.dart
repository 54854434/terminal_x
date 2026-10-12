import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_continuous_flow_clock.dart';

void main() {
  test('100x renders 1.67 minutes per real second, not 100 candles', () {
    final clock = TxContinuousFlowClock(speed: 100)..resume();
    var commits = 0;
    for (var i = 0; i < 60; i++) {
      final frame = clock.advance(const Duration(milliseconds: 16));
      if (frame.needsMinuteCommit) {
        commits++;
        clock.completeMinuteCommit();
      }
    }
    // This loop supplies 960ms of real time; truncating a crossing frame
    // deliberately slows throughput slightly, rather than fast-forwarding.
    expect(commits, 1);
    expect(clock.second, inInclusiveRange(0, 59));
  });

  test('provisional movement is continuous and does not mutate ledger', () {
    final clock = TxContinuousFlowClock(speed: 100)..resume();
    final samples = <double>[];
    for (var i = 0; i < 32; i++) {
      final frame = clock.advance(const Duration(milliseconds: 16));
      expect(frame.needsMinuteCommit, isFalse);
      samples.add(frame.fractionOfMinute);
    }
    expect(samples.first, greaterThan(0));
    expect(samples.last, lessThan(1));
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i], greaterThan(samples[i - 1]));
    }
  });

  test('pause freezes exactly at fractional progress and speed may change', () {
    final clock = TxContinuousFlowClock(speed: 100)..resume();
    clock.advance(const Duration(milliseconds: 123));
    final stoppedAt = clock.minuteProgress;
    clock.pause();
    final paused = clock.advance(const Duration(seconds: 300));
    expect(paused.fractionOfMinute, stoppedAt);
    expect(paused.needsMinuteCommit, isFalse);
    clock.setSpeed(120);
    clock.resume();
    expect(clock.advance(const Duration(milliseconds: 100)).fractionOfMinute,
        greaterThan(stoppedAt));
  });

  test('slow transaction blocks further progression, never queues a second', () {
    final clock = TxContinuousFlowClock(speed: 600)..resume();
    expect(clock.advance(const Duration(milliseconds: 100))
        .needsMinuteCommit, isTrue);
    for (var i = 0; i < 100; i++) {
      final frame = clock.advance(const Duration(seconds: 2));
      expect(frame.needsMinuteCommit, isFalse);
      expect(frame.second, 59);
      expect(frame.isWaitingForStorage, isTrue);
    }
    clock.pause();
    clock.completeMinuteCommit();
    expect(clock.running, isFalse);
    expect(clock.second, 0);
    expect(clock.advance(const Duration(seconds: 2)).needsMinuteCommit,
        isFalse);
  });

  test('ambiguous SQLite failure blocks future progression and resume', () {
    final clock = TxContinuousFlowClock(speed: 100)..resume();
    expect(clock.advance(const Duration(milliseconds: 600))
        .needsMinuteCommit, isTrue);
    clock.storageFailed();
    expect(clock.faulted, isTrue);
    expect(() => clock.resume(), throwsStateError);
    expect(clock.advance(const Duration(seconds: 200))
        .needsMinuteCommit, isFalse);
  });

  test('unresolved SQLite minute blocks premature resume and speed change', () {
    final clock = TxContinuousFlowClock(speed: 100)..resume();
    expect(clock.advance(const Duration(milliseconds: 600))
        .needsMinuteCommit, isTrue);
    clock.pause();
    expect(clock.running, isFalse);
    expect(clock.awaitingCommit, isTrue);
    expect(() => clock.resume(), throwsStateError);
    expect(() => clock.setSpeed(600), throwsStateError);
    expect(clock.speed, 100);
    // Pausing does not roll back an already-started atomic transaction.
    clock.completeMinuteCommit();
    expect(clock.second, 0);
    clock.setSpeed(600);
    clock.resume();
    expect(clock.advance(const Duration(milliseconds: 100))
        .needsMinuteCommit, isTrue);
  });

  test('failed storage minute also refuses speed changes', () {
    final clock = TxContinuousFlowClock(speed: 100)..resume();
    clock.advance(const Duration(milliseconds: 600));
    clock.storageFailed();
    expect(() => clock.setSpeed(120), throwsStateError);
    expect(() => clock.resume(), throwsStateError);
  });

  test('120x requests exactly one minute per 500ms', () {
    final clock = TxContinuousFlowClock(speed: 120)..resume();
    for (var i = 0; i < 49; i++) {
      expect(clock.advance(const Duration(milliseconds: 10))
          .needsMinuteCommit, isFalse);
    }
    expect(clock.second, 58);
    expect(clock.advance(const Duration(milliseconds: 10))
        .needsMinuteCommit, isTrue);
    clock.pause();
    clock.completeMinuteCommit();
    expect(clock.running, isFalse);
    expect(clock.second, 0);
  });

  test('3600x cannot queue extra commits during a slow transaction', () {
    final clock = TxContinuousFlowClock(speed: 3600)..resume();
    expect(clock.advance(const Duration(milliseconds: 17))
        .needsMinuteCommit, isTrue);
    for (var n = 0; n < 1000; n++) {
      expect(clock.advance(const Duration(seconds: 10))
          .needsMinuteCommit, isFalse);
    }
    clock.completeMinuteCommit();
    expect(clock.advance(const Duration(milliseconds: 17))
        .needsMinuteCommit, isTrue);
  });

  test('p95 commit metrics retain at most 64 samples after 10000 commits', () {
    final window = TxCommitLatencyWindow();
    expect(window.p95Milliseconds, 0);
    for (var i = 1; i <= 10000; i++) {
      window.add(Duration(milliseconds: i));
    }
    expect(window.count, 64);
    expect(window.p95Milliseconds, 9997);
    expect(() => TxCommitLatencyWindow(capacity: 0), throwsArgumentError);
    expect(() => TxCommitLatencyWindow(capacity: -1), throwsArgumentError);
    expect(() => window.add(const Duration(milliseconds: -1)),
        throwsArgumentError);
  });

  test('bad speed and elapsed duration are rejected', () {
    expect(() => TxContinuousFlowClock(speed: 0), throwsArgumentError);
    expect(() => TxContinuousFlowClock(speed: 360001), throwsArgumentError);
    expect(() => TxContinuousFlowClock().advance(
        const Duration(milliseconds: -1)), throwsArgumentError);
  });
}
