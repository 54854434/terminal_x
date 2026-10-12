import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../market/tx_candle_history.dart';
import '../market/tx_indicators.dart';

/// Committed candles only, with SMA5/SMA10/SMA20 overlays.
/// The optional dashed quote is a provisional *indicative* mid-minute mark,
/// never silently added to committed OHLC or real trading volume.
class TxCandleChart extends StatefulWidget {
  const TxCandleChart({super.key, required this.candles,
      this.indicativePriceCents});

  final List<TxCandle> candles;
  final int? indicativePriceCents;

  @override
  State<TxCandleChart> createState() => _TxCandleChartState();
}

class _TxCandleChartState extends State<TxCandleChart> {
  int _window = 32;
  int _olderOffset = 0;
  double _dragAccumulator = 0;
  bool _showMA = true;

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
      return const SizedBox(height: 225,
          child: Center(child: Text('暂无已保存的模拟行情记录')));
    }
    final end = (candles.length - _olderOffset).clamp(1, candles.length).toInt();
    final start = math.max(0, end - _window);
    final visible = candles.sublist(start, end);
    final ma5 = _showMA ? TxIndicators.sma(candles, 5).sublist(start, end) : null;
    final ma10 = _showMA ? TxIndicators.sma(candles, 10).sublist(start, end) : null;
    final ma20 = _showMA ? TxIndicators.sma(candles, 20).sublist(start, end) : null;
    final preview = _olderOffset == 0 ? widget.indicativePriceCents : null;
    return Column(children: [
      Row(children: [
        const Text('模拟 K 线 · 1分钟', style: TextStyle(fontSize: 12,
            color: Colors.white70)),
        const Spacer(),
        Text('步 ${visible.first.step}–${visible.last.step}',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
      Row(children: [
        FilterChip(label: const Text('MA5 / MA10 / MA20',
            style: TextStyle(fontSize: 11)),
          selected: _showMA,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() => _showMA = v)),
        const SizedBox(width: 6),
        if (preview != null) const Expanded(child: Text('空心K/虚线：指示价（非成交）',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.white54))),
      ]),
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
        child: RepaintBoundary(child: SizedBox(
          height: 230, width: double.infinity,
          child: CustomPaint(painter: _CandlePainter(visible,
            ma5: ma5, ma10: ma10, ma20: ma20,
            indicativePriceCents: preview)),
        )),
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
  _CandlePainter(this.candles, {this.ma5, this.ma10, this.ma20,
      this.indicativePriceCents});
  final List<TxCandle> candles;
  final List<double?>? ma5, ma10, ma20;
  final int? indicativePriceCents;

  static const rise = Color(0xFF32D0A1);
  static const fall = Color(0xFFFF647C);
  static const grid = Color(0xFF293448);
  static const maShort = Color(0xFFF5C54D);
  static const maMedium = Color(0xFF7E9DFF);
  static const maLong = Color(0xFFE38FE8);

  void _label(Canvas canvas, String value, Offset point) {
    final t = TextPainter(text: TextSpan(text: value,
      style: const TextStyle(color: Color(0xFF9BA7BB), fontSize: 10)),
      textDirection: TextDirection.ltr)..layout();
    t.paint(canvas, point);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.width < 80 || size.height < 100) return;
    final plotRight = size.width - 55;
    final plotHeight = size.height - 52;
    var high = candles.first.highCents.toDouble();
    var low = candles.first.lowCents.toDouble();
    var peakVolume = 0;
    for (final c in candles) {
      high = math.max(high, c.highCents.toDouble());
      low = math.min(low, c.lowCents.toDouble());
      peakVolume = math.max(peakVolume, c.volumeShares);
    }
    if (indicativePriceCents != null) {
      high = math.max(high, indicativePriceCents!.toDouble());
      low = math.min(low, indicativePriceCents!.toDouble());
    }
    for (final series in [ma5,ma10,ma20]) {
      if (series == null) continue;
      for (final v in series) {
        if (v == null) continue;
        high = math.max(high, v);
        low = math.min(low, v);
      }
    }
    final padding = math.max(2.0, (high - low) * 0.08);
    final priceHigh = high + padding;
    final range = math.max(1.0, high - low + padding * 2);
    double y(double price) => (priceHigh - price) / range * plotHeight;

    for (var tick = 0; tick <= 4; tick++) {
      final yy = plotHeight * tick / 4;
      canvas.drawLine(Offset(0, yy), Offset(plotRight, yy),
          Paint()..color = grid..strokeWidth = 0.8);
      _label(canvas, ((priceHigh - range * tick / 4) / 100)
          .toStringAsFixed(2), Offset(plotRight + 6, yy - 6));
    }
    final barWidth = plotRight / (candles.length +
        (indicativePriceCents == null ? 0 : 1));
    final bodyWidth = math.max(2.0, math.min(barWidth * .62, 14.0));
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = barWidth * (i + .5);
      final color = c.rising ? rise : fall;
      final paint = Paint()..color = color..strokeWidth = 1.3;
      canvas.drawLine(Offset(x, y(c.highCents.toDouble())),
          Offset(x, y(c.lowCents.toDouble())), paint);
      final upper = y(math.max(c.openCents, c.closeCents).toDouble());
      final lower = y(math.min(c.openCents, c.closeCents).toDouble());
      canvas.drawRect(Rect.fromLTWH(x - bodyWidth/2, upper,
          bodyWidth, math.max(1.5, lower-upper)), paint);
      if (peakVolume > 0) {
        final volumeHeight = 27 * c.volumeShares / peakVolume;
        canvas.drawRect(Rect.fromLTWH(x-bodyWidth/2,
            size.height - 33 + (27-volumeHeight),
            bodyWidth, volumeHeight), Paint()..color = color.withAlpha(125));
      }
    }

    // Hollow forming bar: a preview only, never a historical candle.
    // Its body reflects the uncommitted quote, not invented executions.
    if (indicativePriceCents != null) {
      final px = barWidth * (candles.length + .5);
      final opening = candles.last.closeCents.toDouble();
      final indicative = indicativePriceCents!.toDouble();
      final top = y(math.max(opening, indicative));
      final bottom = y(math.min(opening, indicative));
      final outline = Paint()
        ..color = const Color(0xFF54CEE5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawRect(Rect.fromLTWH(px - bodyWidth / 2, top,
          bodyWidth, math.max(2.0, bottom - top)), outline);
    }

    void drawMA(List<double?>? values, Color color) {
      if (values == null) return;
      final path = Path();
      var started = false;
      for (var i = 0; i < values.length; i++) {
        final price = values[i];
        if (price == null) {started = false; continue;}
        final px = barWidth * (i + .5), py = y(price);
        if (!started) {path.moveTo(px,py); started = true;}
        else {path.lineTo(px,py);}
      }
      canvas.drawPath(path, Paint()..color = color..strokeWidth = 1.4
          ..style = PaintingStyle.stroke..isAntiAlias = true);
    }
    drawMA(ma5, maShort);
    drawMA(ma10, maMedium);
    drawMA(ma20, maLong);

    if (indicativePriceCents != null) {
      final yy = y(indicativePriceCents!.toDouble());
      final p = Paint()..color = const Color(0xFF54CEE5).withAlpha(170)
          ..strokeWidth = 1.0;
      for (double x = 0; x < plotRight; x += 10) {
        canvas.drawLine(Offset(x, yy), Offset(math.min(x+5, plotRight), yy),p);
      }
    }
    canvas.drawLine(Offset(0, size.height - 33),
        Offset(plotRight, size.height - 33), Paint()..color = grid);
    _label(canvas, '第 ${candles.first.step} 步', Offset(2,size.height - 18));
    _label(canvas, '第 ${candles.last.step} 步',
        Offset(math.max(2.0, plotRight-68),size.height - 18));
    _label(canvas, '量', Offset(plotRight+8,size.height - 32));
  }

  @override
  bool shouldRepaint(covariant _CandlePainter other) =>
      !identical(candles, other.candles) ||
      indicativePriceCents != other.indicativePriceCents ||
      (ma5 == null) != (other.ma5 == null);
}
