import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../market/tx_candle_history.dart';

/// Swipe horizontally to inspect older candles. Drag the zoom slider to change
/// the visible step window. Prices are compiled from SQLite revisions.
class TxCandleChart extends StatefulWidget {
  const TxCandleChart({super.key, required this.candles});

  final List<TxCandle> candles;

  @override
  State<TxCandleChart> createState() => _TxCandleChartState();
}

class _TxCandleChartState extends State<TxCandleChart> {
  int _window = 32;
  int _olderOffset = 0;
  double _dragAccumulator = 0;

  int get _maxOffset => math.max(0, widget.candles.length -
      math.min(_window, widget.candles.length));

  @override
  void didUpdateWidget(covariant TxCandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_olderOffset > _maxOffset) _olderOffset = _maxOffset;
  }

  @override
  Widget build(BuildContext context) {
    final candles = widget.candles;
    if (candles.isEmpty) {
      return const SizedBox(
        height: 225,
        child: Center(child: Text('暂无已保存的模拟行情记录')),
      );
    }
    final end = (candles.length - _olderOffset).clamp(1, candles.length).toInt();
    final start = math.max(0, end - _window);
    final visible = candles.sublist(start, end);
    return Column(children: [
      Row(children: [
        const Text('模拟 K 线 · 逐步聚合', style: TextStyle(fontSize: 12,
            color: Colors.white70)),
        const Spacer(),
        Text('步 ${visible.first.step}–${visible.last.step}',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
      const SizedBox(height: 6),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          _dragAccumulator += details.delta.dx;
          final change = (_dragAccumulator / 14).truncate();
          if (change == 0) return;
          _dragAccumulator -= change * 14;
          setState(() => _olderOffset =
              (_olderOffset + change).clamp(0, _maxOffset).toInt());
        },
        child: SizedBox(
          height: 230,
          width: double.infinity,
          child: CustomPaint(
            painter: _CandlePainter(visible),
          ),
        ),
      ),
      Row(children: [
        const Text('缩放', style: TextStyle(fontSize: 12)),
        Expanded(child: Slider(
          value: _window.toDouble(), min: 12, max: 80, divisions: 17,
          label: '$_window 根',
          onChanged: (value) => setState(() {
            _window = value.round();
            _olderOffset = _olderOffset.clamp(0, _maxOffset).toInt();
          }),
        )),
        Text('$_window', style: const TextStyle(fontSize: 12)),
      ]),
    ]);
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles);
  final List<TxCandle> candles;

  static const rise = Color(0xFF32D0A1);
  static const fall = Color(0xFFFF647C);
  static const grid = Color(0xFF293448);

  void _label(Canvas canvas, String value, Offset point) {
    final text = TextPainter(
      text: TextSpan(text: value,
        style: const TextStyle(color: Color(0xFF9BA7BB), fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, point);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.width < 80 || size.height < 100) return;
    final plotRight = size.width - 55;
    final plotHeight = size.height - 52;
    final high = candles.map((c) => c.highCents).reduce(math.max);
    final low = candles.map((c) => c.lowCents).reduce(math.min);
    final padding = math.max(2.0, (high - low).toDouble() * 0.08);
    final priceHigh = high + padding;
    final priceLow = low - padding;
    final range = math.max(1.0, priceHigh - priceLow);
    double y(double price) => (priceHigh - price) / range * plotHeight;

    for (var tick = 0; tick <= 4; tick++) {
      final yy = plotHeight * tick / 4;
      canvas.drawLine(Offset(0, yy), Offset(plotRight, yy),
          Paint()..color = grid..strokeWidth = 0.8);
      final labelPrice = (priceHigh - range * tick / 4) / 100;
      _label(canvas, labelPrice.toStringAsFixed(2), Offset(plotRight + 6, yy - 6));
    }
    final barWidth = plotRight / candles.length;
    final bodyWidth = math.max(2.0, math.min(barWidth * .62, 14.0));
    final peakVolume = candles.map((c) => c.volumeShares).reduce(math.max);

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = barWidth * (i + .5);
      final color = c.rising ? rise : fall;
      final paint = Paint()..color = color..strokeWidth = 1.3;
      canvas.drawLine(Offset(x, y(c.highCents.toDouble())),
          Offset(x, y(c.lowCents.toDouble())), paint);
      final upper = y(math.max(c.openCents, c.closeCents).toDouble());
      final lower = y(math.min(c.openCents, c.closeCents).toDouble());
      canvas.drawRect(Rect.fromLTWH(x - bodyWidth / 2, upper,
          bodyWidth, math.max(1.5, lower - upper)), paint);
      if (peakVolume > 0) {
        final volumeHeight = 27 * c.volumeShares / peakVolume;
        canvas.drawRect(Rect.fromLTWH(x - bodyWidth / 2,
            size.height - 33 + (27 - volumeHeight), bodyWidth, volumeHeight),
            Paint()..color = color.withAlpha(125));
      }
    }
    canvas.drawLine(Offset(0, size.height - 33),
        Offset(plotRight, size.height - 33), Paint()..color = grid);
    _label(canvas, '第 ${candles.first.step} 步',
        Offset(2, size.height - 18));
    _label(canvas, '第 ${candles.last.step} 步',
        Offset(math.max(2.0, plotRight - 68), size.height - 18));
    _label(canvas, '量', Offset(plotRight + 8, size.height - 32));
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) =>
      !identical(candles, oldDelegate.candles);
}
