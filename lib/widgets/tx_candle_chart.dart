import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../market/tx_candle_history.dart';
import '../market/tx_indicators.dart';

/// Committed simulated OHLC (real fills plus explicitly marked reference
/// prices for no-trade periods) with a distinct indicative preview.
class TxCandleChart extends StatefulWidget {
  const TxCandleChart({super.key, required this.candles, this.indicativePriceCents});
  final List<TxCandle> candles;
  final int? indicativePriceCents;
  @override
  State<TxCandleChart> createState() => _TxCandleChartState();
}

class _TxCandleChartState extends State<TxCandleChart> {
  int _window = 32, _olderOffset = 0;
  double _dragAccumulator = 0;
  bool _showMA = true;
  int _maLength = -1, _maFirstStep = -1;
  TxCandle? _maLast;
  List<double?>? _ma5, _ma10, _ma20;
  int? _previewStep, _previewHigh, _previewLow;
  int get _maxOffset => math.max(0, widget.candles.length -
      math.min(_window, widget.candles.length));

  void _refreshCache() {
    final data = widget.candles;
    if (data.isEmpty) return;
    // This view may be the SAME List object after a successful SQLite commit.
    if (_maLength != data.length || _maFirstStep != data.first.step ||
        !identical(_maLast, data.last)) {
      _maLength = data.length;
      _maFirstStep = data.first.step;
      _maLast = data.last;
      _ma5 = TxIndicators.sma(data, 5);
      _ma10 = TxIndicators.sma(data, 10);
      _ma20 = TxIndicators.sma(data, 20);
    }
    final step = data.last.step;
    if (_previewStep != step) {
      _previewStep = step;
      _previewHigh = data.last.closeCents;
      _previewLow = data.last.closeCents;
    }
    final price = widget.indicativePriceCents;
    if (price != null) {
      _previewHigh = math.max(_previewHigh!, price);
      _previewLow = math.min(_previewLow!, price);
    }
  }

  @override
  void didUpdateWidget(covariant TxCandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles)) {
      // Switching symbols must discard the previous security's indicative
      // extrema; otherwise the price axis shows a fictitious large wick.
      _previewStep = null;
      _maLength = -1;
      _olderOffset = 0;
    }
    if (_olderOffset > _maxOffset) _olderOffset = _maxOffset;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return const SizedBox(height: 225,
          child: Center(child: Text('暂无已保存的模拟行情记录')));
    }
    _refreshCache();
    final all = widget.candles;
    final end = (all.length - _olderOffset).clamp(1, all.length).toInt();
    final start = math.max(0, end - _window);
    final visible = all.sublist(start, end);
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
            style: TextStyle(fontSize: 11)), selected: _showMA,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => _showMA = v)),
        const SizedBox(width: 6),
        if (preview != null) const Expanded(child: Text('空心K/虚线：指示价（非成交）',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.white54))),
      ]),
      GestureDetector(behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          _dragAccumulator += details.delta.dx;
          final shift = (_dragAccumulator / 14).truncate();
          if (shift == 0) return;
          _dragAccumulator -= shift * 14;
          setState(() => _olderOffset =
              (_olderOffset + shift).clamp(0, _maxOffset).toInt());
        },
        child: RepaintBoundary(child: SizedBox(height: 230,
          width: double.infinity,
          child: CustomPaint(painter: _CandlePainter(visible,
            ma5: _showMA ? _ma5!.sublist(start, end) : null,
            ma10: _showMA ? _ma10!.sublist(start, end) : null,
            ma20: _showMA ? _ma20!.sublist(start, end) : null,
            indicativePriceCents: preview,
            indicativeHighCents: preview == null ? null : _previewHigh,
            indicativeLowCents: preview == null ? null : _previewLow)),
        )),
      ),
      Row(children: [
        const Text('缩放', style: TextStyle(fontSize: 12)),
        Expanded(child: Slider(value: _window.toDouble(), min: 12, max: 80,
          divisions: 17, label: '$_window 根',
          onChanged: (v) => setState(() {
            _window = v.round();
            _olderOffset = _olderOffset.clamp(0, _maxOffset).toInt();
          }))),
        Text('$_window', style: const TextStyle(fontSize: 12)),
      ]),
      const Text('无影线：极值未越过实体；零成交只作参考标价、不造量',
          style: TextStyle(color: Colors.white54, fontSize: 10)),
    ]);
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles, {this.ma5, this.ma10, this.ma20,
    this.indicativePriceCents, this.indicativeHighCents,
    this.indicativeLowCents});
  final List<TxCandle> candles;
  final List<double?>? ma5, ma10, ma20;
  final int? indicativePriceCents, indicativeHighCents, indicativeLowCents;
  static const rise = Color(0xFF32D0A1), fall = Color(0xFFFF647C);
  static const grid = Color(0xFF293448),
      shortMA = Color(0xFFF5C54D), mediumMA = Color(0xFF7E9DFF),
      longMA = Color(0xFFE38FE8);

  void _label(Canvas canvas, String value, Offset point) {
    final text = TextPainter(text: TextSpan(text: value,
        style: const TextStyle(color: Color(0xFF9BA7BB), fontSize: 10)),
      textDirection: TextDirection.ltr)..layout();
    text.paint(canvas, point);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.width < 80 || size.height < 100) return;
    final right = size.width - 55, height = size.height - 52;
    double high = candles.first.highCents.toDouble();
    double low = candles.first.lowCents.toDouble();
    var maxVolume = 0;
    for (final c in candles) {
      high = math.max(high, c.highCents.toDouble());
      low = math.min(low, c.lowCents.toDouble());
      maxVolume = math.max(maxVolume, c.volumeShares);
    }
    if (indicativePriceCents != null) {
      high = math.max(high, indicativeHighCents!.toDouble());
      low = math.min(low, indicativeLowCents!.toDouble());
    }
    for (final series in [ma5, ma10, ma20]) {
      if (series == null) continue;
      for (final v in series) {
        if (v != null) {high = math.max(high, v); low = math.min(low, v);}
      }
    }
    final margin = math.max(2.0, (high-low)*.08);
    final priceTop = high + margin, span = math.max(1.0, high-low+2*margin);
    double y(double price) => (priceTop-price)/span*height;
    for (var t=0; t<=4; t++) {
      final h=height*t/4;
      canvas.drawLine(Offset(0,h), Offset(right,h),
          Paint()..color=grid..strokeWidth=.8);
      _label(canvas, ((priceTop-span*t/4)/100).toStringAsFixed(2),
          Offset(right+6,h-6));
    }
    // Fixed spare slot eliminates the horizontal jump at each minute boundary.
    final bar = right/(candles.length+1);
    final body = math.max(2.0,math.min(bar*.62,14.0));
    for (var i=0; i<candles.length; i++) {
      final c=candles[i], x=bar*(i+.5);
      final color=c.rising ? rise : fall;
      final paint=Paint()..color=color..strokeWidth=1.5;
      // Stored OHLC only; a flat bar gets no fabricated wick.
      canvas.drawLine(Offset(x,y(c.highCents.toDouble())),
          Offset(x,y(c.lowCents.toDouble())),paint);
      final top=y(math.max(c.openCents,c.closeCents).toDouble());
      final bottom=y(math.min(c.openCents,c.closeCents).toDouble());
      canvas.drawRect(Rect.fromLTWH(x-body/2,top,body,
          math.max(1.5,bottom-top)),paint);
      if (maxVolume>0 && c.volumeShares>0) {
        final vh=27*c.volumeShares/maxVolume;
        canvas.drawRect(Rect.fromLTWH(x-body/2,size.height-33+(27-vh),
            body,vh),Paint()..color=color.withAlpha(125));
      }
    }
    if (indicativePriceCents!=null) {
      final x=bar*(candles.length+.5);
      final open=candles.last.closeCents.toDouble();
      final mark=indicativePriceCents!.toDouble();
      final top=y(math.max(open,mark));
      final bottom=y(math.min(open,mark));
      final p=Paint()..color=const Color(0xFF54CEE5)
          ..style=PaintingStyle.stroke..strokeWidth=1.6;
      canvas.drawLine(Offset(x,y(indicativeHighCents!.toDouble())),
          Offset(x,y(indicativeLowCents!.toDouble())),p);
      canvas.drawRect(Rect.fromLTWH(x-body/2,top,body,
          math.max(2.0,bottom-top)),p);
      final yy=y(mark);
      for (double dx=0;dx<right;dx+=10) {
        canvas.drawLine(Offset(dx,yy),Offset(math.min(dx+5,right),yy),
            Paint()..color=const Color(0xFF54CEE5).withAlpha(170));
      }
    }
    void drawMA(List<double?>? values,Color color) {
      if (values==null) return;
      final path=Path(); var started=false;
      for (var i=0;i<values.length;i++) {
        final price=values[i];
        if (price==null) {started=false;continue;}
        final px=bar*(i+.5),py=y(price);
        if (!started) {path.moveTo(px,py);started=true;}
        else {path.lineTo(px,py);}
      }
      canvas.drawPath(path,Paint()..color=color..strokeWidth=1.4
        ..style=PaintingStyle.stroke..isAntiAlias=true);
    }
    drawMA(ma5,shortMA);drawMA(ma10,mediumMA);drawMA(ma20,longMA);
    canvas.drawLine(Offset(0,size.height-33),Offset(right,size.height-33),
        Paint()..color=grid);
    _label(canvas,'第 ${candles.first.step} 步',Offset(2,size.height-18));
    _label(canvas,'第 ${candles.last.step} 步',
        Offset(math.max(2.0,right-68),size.height-18));
    _label(canvas,'量',Offset(right+8,size.height-32));
  }

  @override
  bool shouldRepaint(covariant _CandlePainter other) =>
      indicativePriceCents!=other.indicativePriceCents ||
      indicativeHighCents!=other.indicativeHighCents ||
      indicativeLowCents!=other.indicativeLowCents ||
      candles.length!=other.candles.length ||
      (ma5==null)!=(other.ma5==null) ||
      (candles.isNotEmpty && (candles.first.step!=other.candles.first.step ||
          !identical(candles.last,other.candles.last)));
}
