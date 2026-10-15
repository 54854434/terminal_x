import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_frame_render_gate.dart';
void main() {
  test('60Hz clocks notify at every vsync with 14ms limit', () {
    final gate = TxFrameRenderGate();
    var count = 0;
    for (var i = 0; i < 60; i++) {
      if (gate.shouldPaint(Duration(microseconds: 16667 * i))) count++;
    }
    expect(count, 60);
  });
  test('120Hz refresh reduces chart notifications but not clock events', () {
    final gate = TxFrameRenderGate();
    var count = 0;
    for (var i = 0; i < 120; i++) {
      if (gate.shouldPaint(Duration(microseconds: 8333 * i))) count++;
    }
    expect(count, greaterThanOrEqualTo(58));
    expect(count, lessThanOrEqualTo(61));
  });
  test('33ms chart gate remains bounded while high-speed clock keeps moving', () {
    final gate = TxFrameRenderGate(
        minimumInterval: const Duration(milliseconds: 33));
    var count = 0;
    for (var i = 0; i < 60; i++) {
      if (gate.shouldPaint(Duration(microseconds: 16667 * i))) count++;
    }
    expect(count, greaterThanOrEqualTo(29));
    expect(count, lessThanOrEqualTo(31));
  });
  test('committed minute boundary forces preview refresh', () {
    final gate = TxFrameRenderGate();
    expect(gate.shouldPaint(Duration.zero), true);
    expect(gate.shouldPaint(const Duration(milliseconds: 1)), false);
    expect(gate.shouldPaint(const Duration(milliseconds: 2), force: true), true);
  });
  test('pause resets and earlier ticker elapsed triggers fresh paint', () {
    final gate = TxFrameRenderGate();
    expect(gate.shouldPaint(const Duration(milliseconds: 30)), true);
    expect(gate.shouldPaint(const Duration(milliseconds: 31)), false);
    gate.reset();
    expect(gate.shouldPaint(Duration.zero), true);
    expect(gate.shouldPaint(const Duration(milliseconds: 40)), true);
    expect(gate.shouldPaint(const Duration(milliseconds: 2)), true);
  });
  test('negative durations and invalid minimum interval are rejected', () {
    expect(() => TxFrameRenderGate(minimumInterval: Duration.zero),
      throwsArgumentError);
    final gate = TxFrameRenderGate();
    expect(() => gate.shouldPaint(const Duration(microseconds: -1)),
      throwsArgumentError);
  });
}
