import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../market/tx_candle_history.dart';
import '../market/tx_indicators.dart';
import '../market/tx_timeframe.dart';
import '../market/tx_frame_preview.dart';

/// Simulated OHLC (real fills plus explicitly marked reference prices for
/// no-trade periods) with a distinct indicative preview. The live chart can
/// also contain real, explicitly labelled pending observations before SQLite
/// flushes them.
class TxCandleChart extends StatefulWidget {
  const TxCandleChart({super.key, required this.candles,
      this.indicativePriceCents, this.indicativeFramePriceCents,
      this.previewSeconds, this.activeMinuteStep, this.pending = false});
  final List<TxCandle> candles;
  /// A live intraminute candle is already present in [candles].
  final int? activeMinuteStep;
  final int? indicativePriceCents;
  final double? indicativeFramePriceCents;
  final double? previewSeconds;
  final bool pending;
  @override
  State<TxCandleChart> createState() => _TxCandleChartState();
}

class _TxCandleChartState extends State<TxCandleChart> {
  int _window = 32, _olderOffset = 0;
  int? _inspectedStep;
  TxChartPeriod _period = TxChartPeriod.oneMinute;
  TxAggregatedBars? _aggregate;
  List<TxCandle> _activeBars = const <TxCandle>[];
  TxChartPeriod? _cachedPeriod;
  double _dragAccumulator = 0;
  bool _showMA = true;
  int _maLength = -1, _maFirstStep = -1;
  TxCandle? _maLast;
  List<double?>? _ma5, _ma10, _ma20;
  final TxIndicativeWickMemory _indicativeWick = TxIndicativeWickMemory();
  final TxTimelinePreviewTrace _timelineTrace = TxTimelinePreviewTrace();
  int get _maxOffset => math.max(0, _activeBars.length -
      math.min(_window, _activeBars.length));

  void _refreshCache() {
    final source = widget.candles;
    if (source.isEmpty) return;
    final currentStep = widget.activeMinuteStep == source.last.step
        ? source.last.step : source.last.step + 1;
    // The live view is a stable List object mutated on committed revisions.
    // Recompute only for a new revision or a requested interval.
    if (_maLength != source.length ||
        _maFirstStep != source.first.step ||
        !identical(_maLast, source.last) || _cachedPeriod != _period) {
      _maLength = source.length;
      _maFirstStep = source.first.step;
      _maLast = source.last;
      _cachedPeriod = _period;
      _aggregate = TxTimeframe.aggregate(source,
          _period == TxChartPeriod.timeline ? 1 : _period.minutes);
      _activeBars = _aggregate!.bars;
      _ma5 = TxIndicators.sma(_activeBars, 5);
      _ma10 = TxIndicators.sma(_activeBars, 10);
      _ma20 = TxIndicators.sma(_activeBars, 20);
      if (_olderOffset > _maxOffset) _olderOffset = _maxOffset;
    }
    final price = widget.indicativeFramePriceCents ??
        widget.indicativePriceCents?.toDouble();
    if (price != null && widget.previewSeconds != null) {
      _timelineTrace.observe(
        nextMinuteStep: currentStep,
        seconds: widget.previewSeconds!,
        committedCloseCents: source.last.closeCents.toDouble(),
        framePriceCents: price);
    }
    // Timeline uses periodMinutes == 0 as a display-only sentinel. It has
    // a continuous price trace, not a candle bucket or a candle wick.
    // Never pass that sentinel into the positive-period wick accumulator.
    if (_period != TxChartPeriod.timeline) {
      _indicativeWick.observe(
        nextMinuteStep: currentStep,
        periodMinutes: _period.minutes,
        committedCloseCents: source.last.closeCents.toDouble(),
        framePriceCents: price,
      );
    }
  }

  @override
  void didUpdateWidget(covariant TxCandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candles, widget.candles)) {
      // Switching symbols must discard the previous security's indicative
      // extrema; otherwise the price axis shows a fictitious large wick.
      _indicativeWick.reset();
      _timelineTrace.reset();
      _maLength = -1;
      _cachedPeriod = null;
      _olderOffset = 0;
      _inspectedStep = null;
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
    final all = _activeBars;
    final end = (all.length - _olderOffset).clamp(1, all.length).toInt();
    final start = math.max(0, end - _window);
    final visible = all.sublist(start, end);
    TxCandle? inspected;
    for (final bar in visible) {
      if (bar.step == _inspectedStep) { inspected = bar; break; }
    }
    // Preview is a NON-traded reference. Only show it at the far-right edge.
    final preview = _olderOffset == 0
        ? (widget.indicativeFramePriceCents ??
            widget.indicativePriceCents?.toDouble()) : null;
    final projection = preview == null || _period == TxChartPeriod.timeline
        ? null : TxFrameCandleProjection.fromLastCommitted(
            lastAggregated: all.last,
            nextMinuteStep: widget.activeMinuteStep == widget.candles.last.step
                ? widget.activeMinuteStep! : widget.candles.last.step + 1,
            periodMinutes: _period.minutes,
            framePriceCents: preview,
            previewHighCents: _indicativeWick.highCents!,
            previewLowCents: _indicativeWick.lowCents!);
    return Column(children: [
      Row(children: [
        Text(_period == TxChartPeriod.timeline
            ? "模拟分时 · ${widget.pending ? '已保存/待保存' : '已提交'}分钟价格"
            : '模拟 K 线 · ${_period.label}',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        if (widget.pending) ...[
          const SizedBox(width: 6),
          const Text('待保存', style: TextStyle(
              fontSize: 10, color: Colors.amberAccent)),
        ],
        const Spacer(),
        Text('步 ${visible.first.step}–${visible.last.step}',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
      SizedBox(height: 43, child: ListView(
        scrollDirection: Axis.horizontal,
        children: [for (final period in TxChartPeriod.values)
          Padding(padding: const EdgeInsets.only(right: 5),
            child: ChoiceChip(
              label: Text(period.label, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              selected: period == _period,
              onSelected: (_) => setState(() {
                _period = period;
                _olderOffset = 0;
                _inspectedStep = null;
                _cachedPeriod = null;
                _indicativeWick.reset();
              }),
            )),
        ],
      )),
      if (_period.minutes > 1 && _aggregate != null &&
          (_aggregate!.leftIncomplete || _aggregate!.rightIncomplete ||
           _aggregate!.hasGaps))
        const Text('大周期含未完整区间／历史缺口，仅聚合可用分钟',
            style: TextStyle(fontSize: 10, color: Colors.amberAccent)),
      Row(children: [
        FilterChip(label: const Text('MA5 / MA10 / MA20',
            style: TextStyle(fontSize: 11)), selected: _showMA,
            visualDensity: VisualDensity.compact,
            onSelected: _period == TxChartPeriod.timeline ? null :
                (v) => setState(() => _showMA = v)),
        const SizedBox(width: 6),
        if (preview != null && _period != TxChartPeriod.timeline)
          const Expanded(child: Text('绿涨红跌灰平半透明K：指示价（非成交）',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.white54))),
      ]),
      LayoutBuilder(builder: (context, constraints) =>
        GestureDetector(behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final plotWidth = constraints.maxWidth - 55;
          if (plotWidth <= 0 || details.localPosition.dx >= plotWidth) return;
          final slot = plotWidth / (visible.length +
              (_period == TxChartPeriod.timeline ? 0 : 1));
          final index = ((details.localPosition.dx / slot) - .5)
              .round().clamp(0, visible.length - 1).toInt();
          setState(() => _inspectedStep = visible[index].step);
        },
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
          child: CustomPaint(painter: _period == TxChartPeriod.timeline
            ? _TimelinePainter(visible, indicativePriceCents: preview,
                trace: _timelineTrace.sampledForMinuteWidth(
                    math.max(1.0, constraints.maxWidth - 55) /
                    (visible.length + 1)))
            : _CandlePainter(visible,
                ma5: _showMA ? _ma5!.sublist(start, end) : null,
                ma10: _showMA ? _ma10!.sublist(start, end) : null,
                ma20: _showMA ? _ma20!.sublist(start, end) : null,
                indicativePriceCents: projection?.closeCents,
                indicativeHighCents: projection?.highCents,
                indicativeLowCents: projection?.lowCents,
                indicativeOpenCents: projection?.openCents,
                overlayLastCommitted: projection?.overlaysLastCommitted ?? false,
                preferCommittedBody: widget.activeMinuteStep != null,
                // Retain a dotted visual tail for the previous bucket,
                // including 1h/4h/day rollovers; never change real OHLC.
                previousIndicativeStep: _indicativeWick.previousGroupStep,
                previousIndicativeHighCents: _indicativeWick.previousHighCents,
                previousIndicativeLowCents: _indicativeWick.previousLowCents,
                showIndicativeWick: true)),
        )),
      )),
      if (inspected != null)
        Text('区间 ${inspected.step}  O:${(inspected.openCents / 100).toStringAsFixed(2)}'
            '  H:${(inspected.highCents / 100).toStringAsFixed(2)}'
            '  L:${(inspected.lowCents / 100).toStringAsFixed(2)}'
            '  C:${(inspected.closeCents / 100).toStringAsFixed(2)}'
            '  V:${inspected.volumeShares}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.white70)),
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
      Text(widget.pending
          ? '实心 K：真实撮合（含待保存候选）；半透明 K／青色短虚线影线：仅指示价，不进成交与存档'
          : '实心 K：已提交；半透明 K／青色短虚线影线：仅指示价，不进成交与存档',
          style: TextStyle(color: Colors.white54, fontSize: 10)),
    ]);
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles, {this.ma5, this.ma10, this.ma20,
    this.indicativePriceCents, this.indicativeHighCents,
    this.indicativeLowCents, this.indicativeOpenCents,
    this.overlayLastCommitted = false, this.showIndicativeWick = true,
    this.preferCommittedBody = false, this.previousIndicativeStep, this.previousIndicativeHighCents,
    this.previousIndicativeLowCents});
  final List<TxCandle> candles;
  final List<double?>? ma5, ma10, ma20;
  final double? indicativePriceCents, indicativeHighCents,
      indicativeLowCents, indicativeOpenCents;
  final bool overlayLastCommitted;
  final bool showIndicativeWick;
  /// Verified Rust intraminute trades keep the actual OHLC body opaque.
  final bool preferCommittedBody;
  final int? previousIndicativeStep;
  final double? previousIndicativeHighCents, previousIndicativeLowCents;
  static const rise = Color(0xFF32D0A1), fall = Color(0xFFFF647C),
      flat = Color(0xFF9BA7BB);
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
      high = math.max(high, showIndicativeWick
          ? indicativeHighCents!.toDouble() : indicativePriceCents!);
      low = math.min(low, showIndicativeWick
          ? indicativeLowCents!.toDouble() : indicativePriceCents!);
    }
    if (candles.any((c) => c.step == previousIndicativeStep) &&
        previousIndicativeHighCents != null &&
        previousIndicativeLowCents != null) {
      // The ghost wick is separately labelled, never treated as an OHLC.
      high = math.max(high, previousIndicativeHighCents!);
      low = math.min(low, previousIndicativeLowCents!);
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
      final color=_directionColor(c.openCents, c.closeCents);
      final paint=Paint()..color=color..strokeWidth=1.5;
      // The *one* aggregated active candle is painted in cyan below. Do
      // not draw the last committed body underneath it as a fake 1m ghost.
      final hiddenForAggregatePreview = overlayLastCommitted &&
          !preferCommittedBody && showIndicativeWick &&
          indicativePriceCents != null && i == candles.length - 1;
      if (!hiddenForAggregatePreview) canvas.drawLine(Offset(x,y(c.highCents.toDouble())),
          Offset(x,y(c.lowCents.toDouble())),paint);
      final top=y(math.max(c.openCents,c.closeCents).toDouble());
      final bottom=y(math.min(c.openCents,c.closeCents).toDouble());
      if (!hiddenForAggregatePreview) canvas.drawRect(Rect.fromLTWH(x-body/2,top,body,
          math.max(1.5,bottom-top)),paint);
      if (maxVolume>0 && c.volumeShares>0) {
        final vh=27*c.volumeShares/maxVolume;
        canvas.drawRect(Rect.fromLTWH(x-body/2,size.height-33+(27-vh),
            body,vh),Paint()..color=color.withAlpha(125));
      }
    }
    // The previous bucket's UNCOMMITTED extrema are only a dotted optical
    // memory on its verified bar. Never change real bar OHLCV.
    if (candles.any((c) => c.step == previousIndicativeStep) &&
        previousIndicativeHighCents != null &&
        previousIndicativeLowCents != null) {
      final prior = candles.indexWhere(
          (c) => c.step == previousIndicativeStep);
      final last = candles[prior];
      final x = bar * (prior + .5);
      final ghost = Paint()..color = const Color(0xFF54CEE5).withAlpha(160)
          ..strokeWidth = 1.3;
      void dotted(double startY, double endY) {
        for (var yy = startY; yy < endY; yy += 7.0) {
          canvas.drawLine(Offset(x, yy),
              Offset(x, math.min(yy + 4.0, endY)), ghost);
        }
      }
      dotted(y(previousIndicativeHighCents!), y(last.highCents.toDouble()));
      dotted(y(last.lowCents.toDouble()), y(previousIndicativeLowCents!));
    }
    if (indicativePriceCents!=null) {
      final x=bar*(candles.length-(overlayLastCommitted ? .5 : -.5));
      final open=indicativeOpenCents ?? candles.last.closeCents.toDouble();
      final mark=indicativePriceCents!;
      final top=y(math.max(open,mark));
      final bottom=y(math.min(open,mark));
      final color = _directionColor(open, mark);
      final p=Paint()..color=color.withAlpha(175)..strokeWidth=1.6;
      if (showIndicativeWick &&
          !(overlayLastCommitted && preferCommittedBody)) {
        final hi = y(indicativeHighCents!);
        final lo = y(indicativeLowCents!);
        if (hi < top) canvas.drawLine(Offset(x, hi), Offset(x, top), p);
        if (lo > bottom) canvas.drawLine(Offset(x, bottom), Offset(x, lo), p);
        // Filled for visual consistency, translucent for provisional status.
        canvas.drawRect(Rect.fromLTWH(x-body/2,top,body,
            math.max(2.0,bottom-top)),p);
      } else {
        canvas.drawCircle(Offset(x, y(mark)), 2.5, p);
      }
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

  Color _directionColor(num open, num close) {
    if (close > open) return rise;
    if (close < open) return fall;
    return flat;
  }

  @override
  bool shouldRepaint(covariant _CandlePainter other) =>
      indicativePriceCents!=other.indicativePriceCents ||
      indicativeHighCents!=other.indicativeHighCents ||
      indicativeLowCents!=other.indicativeLowCents ||
      indicativeOpenCents!=other.indicativeOpenCents ||
      overlayLastCommitted!=other.overlayLastCommitted ||
      preferCommittedBody!=other.preferCommittedBody ||
      showIndicativeWick!=other.showIndicativeWick ||
      previousIndicativeStep!=other.previousIndicativeStep ||
      previousIndicativeHighCents!=other.previousIndicativeHighCents ||
      previousIndicativeLowCents!=other.previousIndicativeLowCents ||
      candles.length!=other.candles.length ||
      (ma5==null)!=(other.ma5==null) ||
      (candles.isNotEmpty && (candles.first.step!=other.candles.first.step ||
          !identical(candles.last,other.candles.last)));
}


/// Minute-closing mark line, not a seconds-level executed trade stream.
/// The final blue dash can be indicative; it is never persisted as a fill.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.candles, {this.indicativePriceCents,
      this.trace = const <TxTimelineTracePoint>[]});
  final List<TxCandle> candles;
  final double? indicativePriceCents;
  final List<TxTimelineTracePoint> trace;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.width < 80 || size.height < 100) return;
    final right = size.width - 55, bottom = size.height - 39;
    var low = candles.first.closeCents.toDouble();
    var high = low;
    for (final item in candles) {
      low = math.min(low, item.closeCents.toDouble());
      high = math.max(high, item.closeCents.toDouble());
    }
    if (indicativePriceCents != null) {
      low = math.min(low, indicativePriceCents!);
      high = math.max(high, indicativePriceCents!);
      for (final sample in trace) {
        low = math.min(low, sample.priceCents);
        high = math.max(high, sample.priceCents);
      }
    }
    final margin = math.max(2.0, (high - low) * .09);
    final top = high + margin;
    final range = math.max(1.0, high - low + 2 * margin);
    double y(double price) => (top - price) / range * bottom;
    final axis = Paint()..color = const Color(0xFF293448)
        ..strokeWidth = .8;
    for (var i = 0; i <= 4; i++) {
      final yy = bottom * i / 4;
      canvas.drawLine(Offset(0, yy), Offset(right, yy), axis);
      final label = TextPainter(text: TextSpan(
        text: ((top - range * i / 4) / 100).toStringAsFixed(2),
        style: const TextStyle(fontSize: 10, color: Color(0xFF9BA7BB))),
        textDirection: TextDirection.ltr)..layout();
      label.paint(canvas, Offset(right + 6, yy - 6));
    }
    // Reserve exactly one full minute on the right for the continuously
    // advancing uncommitted line. The next committed close becomes the new
    // last solid point and the preview starts again from that close.
    final width = right / (candles.length + 1);
    final path = Path();
    for (var i = 0; i < candles.length; i++) {
      final x = width * (i + .5);
      final yy = y(candles[i].closeCents.toDouble());
      if (i == 0) { path.moveTo(x, yy); } else { path.lineTo(x, yy); }
    }
    if (candles.length == 1) {
      canvas.drawCircle(Offset(width * .5, y(candles.first.closeCents.toDouble())),
          2.5, Paint()..color = const Color(0xFF3DD3A5));
    }
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF3DD3A5)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true);
    if (indicativePriceCents != null && trace.isNotEmpty) {
      // Join the LAST verified close to successive intraminute samples.
      // The x coordinate grows monotonically with fractional game seconds,
      // rather than drawing a stationary cyan point on the right border.
      final prevX = width * (candles.length - .5);
      final segment = Path()..moveTo(prevX,
          y(candles.last.closeCents.toDouble()));
      var fromX = prevX;
      var fromY = y(candles.last.closeCents.toDouble());
      for (final sample in trace) {
        final px = prevX + width * (sample.seconds / 60.0);
        final py = y(sample.priceCents);
        if (px <= fromX) continue;
        final dx = px - fromX;
        // Smooth connected line; no pixel-sized zigzags at high speed.
        segment.cubicTo(fromX + dx * .35, fromY,
            fromX + dx * .65, py, px, py);
        fromX = px;
        fromY = py;
      }
      canvas.drawPath(segment, Paint()
        ..color = const Color(0xFF54CEE5)
        ..strokeWidth = 1.9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true);
      final last = trace.last;
      canvas.drawCircle(Offset(prevX + width * last.seconds / 60,
          y(last.priceCents)), 2.7,
          Paint()..color = const Color(0xFF54CEE5));
    }
    final text = TextPainter(text: const TextSpan(
      text: '分时收盘参考价格 / 非逐笔成交',
      style: TextStyle(fontSize: 10, color: Colors.white54)),
      textDirection: TextDirection.ltr)..layout();
    text.paint(canvas, Offset(4, size.height - 24));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      indicativePriceCents != old.indicativePriceCents ||
      !identical(trace,old.trace) ||
      candles.length != old.candles.length ||
      (candles.isNotEmpty &&
          (candles.first.step != old.candles.first.step ||
           !identical(candles.last, old.candles.last)));
}
