/// Terminal X 0.3.0 unified trading interface and position analytics.
/// Existing V0.2 + V0.1 apps and backups are never accessed.
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import 'engine/tx_engine.dart';
import 'engine/tx_session.dart';
import 'market/tx_live_candles.dart';
import 'market/tx_continuous_flow_clock.dart';
import 'market/tx_speed_feedback.dart';
import 'market/tx_simulation_clock.dart';
import 'market/tx_realtime_clock.dart';
import 'market/tx_position_analytics.dart';
import 'market/tx_portfolio_risk.dart';
import 'market/tx_order_book_insight.dart';
import 'market/tx_execution_estimate.dart';
import 'market/tx_ticket_sizing.dart';
import 'market/tx_frame_preview.dart';
import 'market/tx_trade_journal.dart';
import 'market/tx_portfolio_scenarios.dart';
import 'market/tx_runtime_health.dart';
import 'market/tx_market_phase_timeline.dart';
import 'market/tx_frame_render_gate.dart';
import 'market/tx_storage_footprint.dart';
import 'market/tx_market_tape_window.dart';
import 'market/tx_live_portfolio_valuation.dart';
import 'storage/tx_sqlite_store.dart';
import 'storage/tx_delta_codec.dart';
import 'storage/tx_trading_service.dart';
import 'widgets/tx_candle_chart.dart';
import 'widgets/tx_ticket_submit_bar.dart';
import 'widgets/tx_terminal_theme.dart';
import 'widgets/tx_market_hero.dart';
import 'widgets/tx_terminal_status.dart';
import 'widgets/tx_market_radar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TerminalXV024());
}

class TerminalXV024 extends StatelessWidget {
  const TerminalXV024({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Terminal X',
    theme: TxTerminalTheme.dark(),
    home: const TerminalHomeV024(),
  );
}

class TerminalHomeV024 extends StatefulWidget {
  const TerminalHomeV024({super.key});
  @override
  State<TerminalHomeV024> createState() => _TerminalHomeV024State();
}

class _TerminalHomeV024State extends State<TerminalHomeV024>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const green = TxTerminalColors.buy;
  static const red = TxTerminalColors.sell;
  static const appVersion = String.fromEnvironment('TX_APP_VERSION', defaultValue: '0.3.1');
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController(text: '10.00');
  TxTradingService? _trader;
  TxLiveCandles? _candles;
  late final Ticker _playbackTicker;
  Duration? _previousFrame;
  final TxContinuousFlowClock _flow = TxContinuousFlowClock();
  final TxCommittedSpeedWindow _committedSpeed = TxCommittedSpeedWindow();
  final Stopwatch _speedStopwatch = Stopwatch();
  final TxCommitLatencyWindow _commitLatency = TxCommitLatencyWindow();
  final TxFrameRenderGate _frameRenderGate = TxFrameRenderGate();
  TxStorageFootprint? _storageFootprint;
  int _checkpointInterval = TxDeltaCodec.checkpointInterval;
  int _checkpointDraft = TxDeltaCodec.checkpointInterval;
  int? _positionCacheRevision;
  Map<String, TxPosition>? _positionCache;
  int? _journalCacheRevision;
  TxTradeJournal? _journalCache;
  Future<void>? _operation;
  int _page = 0;
  int _symbol = 0;
  int _speed = 1;
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0.0);
  bool _auto = false;
  bool _busy = false;
  bool _loading = true;
  bool _limit = false;
  TxSide _ticketSide = TxSide.buy;
  int _recordMode = 0;
  int _marketTapeRequested = TxMarketTapeWindow.pageSize;
  String _notice = '正在检查 SQLite';
  String? _fault;

  bool get _ready => !_loading && !_busy && _fault == null &&
      _trader != null && !_trader!.blocked;
  String get _symbolName => TxSession.symbols[_symbol];
  String money(int cents) => (cents / 100).toStringAsFixed(2);
  String signedMoney(int cents) => '${cents >= 0 ? '+' : '-'}¥${money(cents.abs())}';
  double _indication(TxSession session, double seconds) => TxFrameQuote.cents(
      session.lastPrice(_symbolName), session.step, seconds, _symbol);


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackTicker = createTicker(_onPlaybackFrame);
    // Paint the first loading frame before opening a long historical store.
    // DB verification is required, but must not block the Flutter first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  // A pause is never gated by _busy. An in-flight atomic SQLite write is
  // allowed to settle, but no more game minutes are scheduled after the tap.
  void _pause() {
    if (mounted) _playbackTicker.stop();
    _previousFrame = null;
    _frameRenderGate.reset();
    _flow.pause();
    _speedStopwatch.stop();
    if (_auto && mounted) setState(() => _auto = false);
  }

  // Vsync advances ONLY provisional time. The chart's cyan preview never
  // adds a fill, cash transaction or committed OHLCV observation.
  void _onPlaybackFrame(Duration elapsed) {
    if (!mounted || !_auto || _fault != null) return;
    final previous = _previousFrame;
    // Keep the Ticker alive during SQLite I/O, but drop elapsed wall time
    // while the one-and-only minute commit is unresolved. Never catch up
    // by skipping economic minutes or advancing uncommitted ledger time.
    _previousFrame = elapsed;
    if (_busy || _flow.awaitingCommit || previous == null) return;
    final delta = elapsed - previous;
    if (delta.isNegative) return;
    final frame = _flow.advance(delta);
    // Game time derives from real frame delta, never from a fixed
    // seconds-per-frame assumption. Emit fractional seconds at any FPS.
    final frameSeconds = frame.fractionOfMinute * 60.0;
    // Time advances on every vsync; only cyan preview repaint is limited.
    if (_frameRenderGate.shouldPaint(elapsed,
        force: frame.needsMinuteCommit) && frameSeconds != _seconds.value) {
      _seconds.value = frameSeconds;
    }
    if (frame.needsMinuteCommit) {
      // Do not stop/restart the vsync ticker every single SQLite minute.
      // The next frames are ignored until this durable commit completes.
      // Backpressure lowers achieved speed without inventing transactions.
      _tick(automatic: true);
    }
  }

  void _toggle() {
    if (_auto) {
      _pause();
      return;
    }
    if (!_ready || _flow.awaitingCommit || _flow.faulted) return;
    _flow.setSpeed(_speed);
    _flow.resume();
    _committedSpeed.reset();
    _speedStopwatch..reset()..start();
    _committedSpeed.record(elapsedMilliseconds: 0,
        minute: _trader!.current.session.step);
    setState(() {
      _auto = true;
    });
    _previousFrame = null;
    _frameRenderGate.reset();
    _playbackTicker.start();
  }

  Future<void> _open() async {
    TxTradingService? service;
    try {
      final dir = await getApplicationSupportDirectory();
      final sqlite = File('${dir.path}/terminal_x_game.sqlite');
      service = TxTradingService(TxSqliteStore(
        NativeDatabase.createInBackground(sqlite)),
        initialSessionFactory: TxSession.freshWithAgents,
        persistentMarketWorker: true);
      final initial = await service.open();
      final checkpointInterval = await service.database.readCheckpointInterval();
      // Once, not on every committed tick. 64 recent revisions are enough to
      // reconstruct recent candles without loading the entire database.
      var candles = await service.database.readCandleIndex(initial);
      if (candles == null) {
        final recent = await service.database.readHistory(limit: 64);
        candles = TxLiveCandles.fromVerifiedHistory(recent);
        await service.database.seedCandleIndex(initial, candles);
      }
      if (!mounted) {
        await service.close();
        return;
      }
      setState(() {
        _trader = service;
        _candles = candles;
        _checkpointInterval = checkpointInterval;
        _checkpointDraft = checkpointInterval;
        _price.text = money(initial.session.lastPrice(_symbolName));
        _notice = '已校验 SQLite 修订 ${initial.revision}，行情默认暂停';
        _loading = false;
      });
    } catch (e) {
      await service?.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fault = 'SQLite 读取或校验失败，已停止交易并保留数据：$e';
      });
    }
  }

  void _operate(Future<String> Function(TxTradingService) work,
      {bool automated = false}) {
    if (!_ready) return;
    // User-initiated operations suspend visual playback before any write.
    if (!automated && _auto) _pause();
    if (!automated) {
      _playbackTicker.stop();
      _previousFrame = null;
      _frameRenderGate.reset();
      setState(() => _busy = true);
    } else {
      // Automatic minute commits stay single-flight, but do not flash a
      // global loading indicator or rebuild the entire UI before each save.
      _busy = true;
    }
    _operation = _perform(work, automated: automated);
  }

  Future<void> _perform(Future<String> Function(TxTradingService) work,
      {required bool automated}) async {
    try {
      final trader = _trader!;
      final before = trader.current;
      final notice = await work(trader);
      final after = trader.current;
      // This operation uses only the previous and current verified states;
      // no readHistory(160) for each game minute.
      if (before.revision != after.revision) {
        for (final symbol in TxSession.symbols) {
          _previousBookQty[symbol] =
              _currentDepthQuantities(before.session, symbol);
        }
        _candles!.addCommit(before, after);
      }
      if (automated) {
        // Transaction finished: only NOW may the minute boundary appear.
        _flow.completeMinuteCommit();
        if (mounted) _seconds.value = 0;
        if (_auto) {
          _committedSpeed.record(
            elapsedMilliseconds: _speedStopwatch.elapsedMilliseconds,
            minute: after.session.step,
          );
        }
        // No arbitrary 60-minute playback cut-off. The database checkpoint
        // interval independently bounds recovery work; every minute still
        // finishes a verified atomic commit before the next minute begins.
      }
      // finally performs the single build for this committed minute.
      // Avoid a second full-page build while displaying the new revision.
      if (mounted) _notice = notice;
    } catch (e) {
      // Whether the DB commit was ambiguous or a chart invariant failed,
      // stop instead of risking another order against stale state.
      _pause();
      _flow.storageFailed();
      if (mounted) setState(() =>
          _fault = '交易或历史检查异常；已暂停并保留数据：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_auto && _fault == null && !_playbackTicker.isActive) {
          // Can occur after an explicit manual operation. Automatic commits
          // never stop the ticker, so this branch is normally unused.
          _previousFrame = null;
          _frameRenderGate.reset();
          _playbackTicker.start();
        }
      }
    }
  }

  void _tick({bool automatic = false}) {
    if (!automatic && _flow.running) _pause();
    if (!automatic && !_flow.awaitingCommit) {
      _flow.resetProvisional();
      _seconds.value = 0;
    }
    _operate((service) async {
    final latency = Stopwatch()..start();
    final next = await service.nextTick();
    latency.stop();
    // Record only successful, durable minute commits, never failed attempts.
    _commitLatency.add(latency.elapsed);
    return '模拟第 ${TxSimulationClock.gameDay(next.session.step)} 天 '
        '${TxSimulationClock.hhmm(next.session.step)} · '
        'SQLite r${next.revision}';
    }, automated: automatic);
  }

  int? _cents(String raw) {
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(raw.trim())) return null;
    final p = raw.trim().split('.');
    final integer = int.tryParse(p.first);
    final fractional = p.length == 1 ? 0 : int.tryParse(p[1].padRight(2, '0'));
    if (integer == null || fractional == null) return null;
    final price = integer * 100 + fractional;
    return price >= 1 && price <= TxEngine.maxPriceCents ? price : null;
  }

  void _trade(TxSide side) {
    final n = int.tryParse(_qty.text.trim());
    final limitPrice = _limit ? _cents(_price.text) : null;
    if (n == null || n <= 0 || n > TxEngine.maxQuantity ||
        (_limit && limitPrice == null)) {
      setState(() => _notice = '请输入有效股数和限价（最多两位小数）');
      return;
    }
    _operate((service) async {
      final order = await service.place(
        symbol: _symbolName, side: side,
        kind: _limit ? TxKind.limit : TxKind.market,
        quantity: n, limitPriceCents: limitPrice);
      return '${order.id} · 成交${order.filled}股，余量${order.remaining}股'
          ' · ${order.status.name}';
    });
  }

  void _cancel(String id) => _operate((service) async {
    await service.cancel(id);
    return '$id 已撤销，冻结已释放';
  });

  // Explicit user action, never called from the frame clock or minute save.
  // Diagnostics are read-only; errors do not invalidate a trading revision.
  void _inspectStorage() {
    _operate((service) async {
      try {
        final pages = await service.database
            .customSelect('PRAGMA page_count').getSingle();
        final pageSize = await service.database
            .customSelect('PRAGMA page_size').getSingle();
        final count = await service.database.customSelect(
          "SELECT COUNT(*) AS n FROM snapshots WHERE session_id = 'primary'")
            .getSingle();
        final latest = await service.database.customSelect(
          "SELECT LENGTH(payload_json) AS bytes FROM snapshots "
          "WHERE session_id = 'primary' ORDER BY revision DESC LIMIT 1")
            .getSingle();
        final footprint = TxStorageFootprint.fromRaw(
          pageCount: pages.read<int>('page_count'),
          pageSize: pageSize.read<int>('page_size'),
          snapshotCount: count.read<int>('n'),
          latestSnapshotBytes: latest.read<int>('bytes'),
          revision: service.current.revision);
        if (mounted) setState(() => _storageFootprint = footprint);
        return 'SQLite 容量诊断完成（只读，不删除旧快照）';
      } catch (e) {
        return '容量诊断未完成，未修改任何存档：$e';
      }
    });
  }

  void _saveCheckpointInterval() {
    final selected = _checkpointDraft;
    _operate((service) async {
      await service.database.setCheckpointInterval(selected);
      if (mounted) setState(() => _checkpointInterval = selected);
      return '完整检查点间隔已设为每 $selected 次成功提交；每笔交易和每个游戏分钟仍会安全保存';
    });
  }

  Widget _title(String t, {String? sub}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 17, 4, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontSize: 17,
          letterSpacing: 0.2, fontWeight: FontWeight.w700)),
      if (sub != null) Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(sub, style: const TextStyle(fontSize: 12,
          color: TxTerminalColors.secondaryText))),
    ]),
  );

  Widget _metric(String label, String value) =>
      TxMetricTile(label: label, value: value);

  Widget _chooseSymbol(TxSession session) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('SIM-A01')),
        ButtonSegment(value: 1, label: Text('SIM-A02')),
      ],
      selected: {_symbol},
      onSelectionChanged: (values) => setState(() {
        _symbol = values.first;
        _price.text = money(session.lastPrice(_symbolName));
      }),
    ),
  );

  // A speed change is applied only between completed durable minute writes.
  void _changeSpeed(int next) {
    if (!_ready || _flow.awaitingCommit || _flow.faulted) return;
    next = next.clamp(1, TxContinuousFlowClock.maxSupportedSpeed).toInt();
    if (_speed == next) return;
    _flow.setSpeed(next);
    _committedSpeed.reset();
    _speedStopwatch..reset();
    if (_auto) {
      _speedStopwatch.start();
      _committedSpeed.record(elapsedMilliseconds: 0,
          minute: _trader!.current.session.step);
    }
    setState(() => _speed = next);
  }

  Future<void> _showCustomSpeed() async {
    if (!_ready) return;
    final controller = TextEditingController(text: '$_speed');
    final choice = await showDialog<int>(context: context, builder: (context) =>
      AlertDialog(title: const Text('自定义游戏倍率'), content: TextField(
        controller: controller, autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            labelText: '1～360000 倍', suffixText: '×')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(
              int.tryParse(controller.text.trim())),
              child: const Text('应用')),
        ]));
    controller.dispose();
    if (!mounted || choice == null || choice < 1 ||
        choice > TxContinuousFlowClock.maxSupportedSpeed) return;
    _changeSpeed(choice);
  }

  // Previous committed book for real post-commit deltas, not simulated orders.
  final Map<String, Map<String, int>> _previousBookQty = {};

  Map<String, int> _currentDepthQuantities(TxSession session, String symbol) {
    final values = <String,int>{};
    for (final side in [TxSide.sell, TxSide.buy]) {
      for (final level in session.engine.depth(symbol, side)) {
        values['${side.name}:${level.priceCents}'] = level.quantity;
      }
    }
    return values;
  }

  Widget _depth(TxSession session) {
    final asks = session.engine.depth(_symbolName, TxSide.sell);
    final bids = session.engine.depth(_symbolName, TxSide.buy);
    final insight = TxOrderBookInsight.fromLevels(bids: bids, asks: asks);
    final quantities = [...asks.map((e) => e.quantity),
      ...bids.map((e) => e.quantity), 1];
    final maxQty = quantities.reduce((a,b) => a > b ? a : b);
    final prior = _previousBookQty[_symbolName];
    Widget level(String label, int cents, int quantity, Color tint,
        TxSide side) {
      final old = prior?['${side.name}:$cents'];
      final change = old == null ? null : quantity - old;
      return InkWell(
      onTap: () => setState(() {
        _limit = true;
        _price.text = money(cents);
        _page = 1;
      }),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
        child: Stack(children: [
          FractionallySizedBox(widthFactor: quantity / maxQty,
              child: Container(height: 22, color: tint.withAlpha(35))),
          Row(children: [
            SizedBox(width: 50, child: Text(label,
                style: TextStyle(fontSize: 12, color: tint))),
            Expanded(child: Text('¥${money(cents)}')),
            Text('$quantity 股'),
            if (prior != null && old == null) Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Text('新挂', style: TextStyle(fontSize: 10, color: tint))),
            if (change != null && change != 0) Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Text('${change > 0 ? '+' : ''}$change',
                style: TextStyle(fontSize: 10,
                  color: change > 0 ? green : red))),
          ]),
        ])),
    );
    }
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('真实五档盘口 · 已提交委托',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('做市商逐分钟真实挂撤单 · 新挂 / + / − 标出提交后变化',
            style: TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 6),
        Text(insight.spreadCents == null
          ? '买卖价差：—（盘口一侧缺少挂单）'
          : '买卖价差 ¥${money(insight.spreadCents!)}'
            ' · ${insight.spreadBasisPoints!.toStringAsFixed(1)} bp',
          style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Text('五档买量 ${insight.bidShares} 股 / ${insight.bidOrders} 笔挂单'
             ' · 卖量 ${insight.askShares} 股 / ${insight.askOrders} 笔挂单',
          style: const TextStyle(fontSize: 11, color: Colors.white70)),
        if (insight.bidShareFraction != null) ...[
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: insight.bidShareFraction!, minHeight: 5,
            backgroundColor: red,
            valueColor: const AlwaysStoppedAnimation<Color>(green)),
          Text('五档买盘量占比 '
              '${(insight.bidShareFraction! * 100).toStringAsFixed(1)}%'
              '（仅可见委托量，不预测涨跌）',
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
        for (var i = asks.length - 1; i >= 0; i--)
          level('卖${i+1}', asks[i].priceCents, asks[i].quantity, red, TxSide.sell),
        const Divider(),
        for (var i = 0; i < bids.length; i++)
          level('买${i+1}', bids[i].priceCents, bids[i].quantity, green, TxSide.buy),
        const Text('点价格可填入限价单',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
      ])),
    );
  }

  String _regimeName(int step, int symbolIndex) {
    final minute = step < 1 ? 1 : step;
    return switch (TxSession.marketRegime(minute, symbolIndex)) {
      0 => '上行趋势',
      1 => '区间震荡',
      2 => '下行趋势',
      _ => '高波动',
    };
  }

  // Market-to-trade shortcuts must set the requested side explicitly.
  // Never inherit the previous ticket's buy/sell direction.
  void _openTradeTicket(TxSide side) => setState(() {
    _ticketSide = side;
    _limit = false;
    _page = 1;
  });

  Widget _market(TxSession session) {
    final minuteFills = session.currentMinuteFills
        .where((f) => f.symbol == _symbolName).toList();
    final minuteVolume = minuteFills.fold<int>(0, (sum, f) => sum + f.quantity);
    final price = session.lastPrice(_symbolName);
    final candles = _candles!.forSymbol(_symbolName);
    return ListView(padding: const EdgeInsets.all(14), children: [
      TxMarketRadar(quotes: [
        for (var i=0;i<TxSession.symbols.length;i++)
          TxRadarQuote(symbol:TxSession.symbols[i],
            priceCents:session.lastPrice(TxSession.symbols[i]),
            regime:_regimeName(session.step,i)),
        ],selectedIndex:_symbol,onSelect:(i)=>setState(() {
          _symbol=i;
          _price.text=money(session.lastPrice(_symbolName));
        })),
      TxMarketHero(symbol: _symbolName, committedPriceCents: price,
        step: session.step, seconds: _seconds,
        indicativeCents: (seconds) => _indication(session, seconds),
        onBuy: () => _openTradeTicket(TxSide.buy),
        onSell: () => _openTradeTicket(TxSide.sell)),
      RepaintBoundary(child: Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<double>(
          valueListenable: _seconds,
          builder: (context, seconds, child) => TxCandleChart(
            candles: candles,
            // At exactly 0 seconds of an automatically running minute,
            // retain the cyan display-only price marker. Otherwise it
            // vanishes for one frame after *every* durable SQLite commit.
            indicativeFramePriceCents: (_auto || seconds > 0)
                ? _indication(session, seconds) : null,
            previewSeconds: (_auto || seconds > 0) ? seconds : null))))),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('模拟市场参与者', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('2 个有限库存做市商 + 4 个独立资金账户的模拟交易者；'
              '它们会主动交易和提供流动性，玩家不操作也可能有成交。',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text('当前市场环境：${_regimeName(session.step, _symbol)}'),
          Text('本游戏分钟：${minuteFills.length} 笔真实撮合 · '
              '$minuteVolume 股成交量'),
          const Text('所有成交均在真实订单簿按价格与时间撮合；'
              '不模拟外部证券、不保证每一分钟都有成交。',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ))),
      _depth(session),
      _phaseTimeline(session.step),
      _title('游戏时间与行情速度', sub: '24 小时制，前台运行；失败或切后台立即暂停'),
      Card(child: Padding(padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: (_auto || _ready) ? _toggle : null,
              icon: Icon(_auto ? Icons.pause : Icons.play_arrow),
              label: Text(_auto ? '暂停' : '运行'),
            )),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _ready ? () => _tick() : null,
                child: const Text('+1 分钟')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _ready ? _showCustomSpeed : null,
              icon: const Icon(Icons.tune, size: 17),
              label: Text('$_speed×')),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final value in [1, 5, 10, 30, 60, 100, 300, 600, 1200, 3600])
                Padding(padding: const EdgeInsets.only(right: 5),
                  child: ChoiceChip(label: Text('$value×'),
                    selected: _speed == value,
                    onSelected: _ready ? (_) => _changeSpeed(value) : null)),
            ])),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final change in [-10, -1, 1, 10])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 5),
                child: OutlinedButton(
                  onPressed: _ready ? () => _changeSpeed(_speed + change) : null,
                  child: Text('${change > 0 ? '+' : ''}$change'))),
          ]),
          const Text('分时逐帧连线为未成交指示价格，不是逐秒真实成交。'
              '目标倍速不等于实际达成倍速；SQLite 慢时自动背压，不补跳。',
              style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 4),
          Text('目标 ${_speed}× · 实际已提交 ${_committedSpeed.achievedMultiplier.toStringAsFixed(1)}×'
              ' · 每分钟安全提交',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          if (_commitLatency.count > 0) ...[
            Text('最近 ${_commitLatency.count} 次有效分钟提交耗时 p95 '
                '${_commitLatency.p95Milliseconds} ms（含撮合及 SQLite）',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Builder(builder: (context) {
              final health=TxRuntimeHealth.evaluate(speed:_speed,
                sampleCount:_commitLatency.count,
                p95Milliseconds:_commitLatency.p95Milliseconds);
              return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('目标 ${_speed}× 每分钟预算 '
                    '${health.budgetMilliseconds.toStringAsFixed(1)} ms'),
                Text(health.budgetExceeded==null ? '样本不足，暂不判断速度' :
                  (health.budgetExceeded! ? '提交 p95 已超理论预算' : '提交 p95 未超理论预算'),
                    style:TextStyle(fontSize:11,color:
                      health.budgetExceeded==true?Colors.amberAccent:
                      TxTerminalColors.secondaryText)),
                const Text('预算为理论估算，实际倍速以已提交进度为准；'
                  '不以丢帧或补跳分钟掩盖存档等待。',
                  style:TextStyle(fontSize:10,
                    color:TxTerminalColors.secondaryText)),
              ]);
            }),
          ],
        ]),
      )),
      const SizedBox(height: 8),
      const Text('分时右端青色连续线及各周期青色空心蜡烛为未结算指示报价；真实 OHLC、均线与成交量均取自已提交记录。'
          '成交量仅统计真实撮合，不把秒级报价变动伪造成交易。',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]);
  }

  Widget _phaseTimeline(int committedMinute) {
    final events = TxMarketPhaseTimeline.recent(currentStep: committedMinute);
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('模拟市场阶段记录',
          style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        const Text('脚本市场环境切换，不是外部新闻或真实成交。',
          style: TextStyle(fontSize: 11, color: Colors.white60)),
        if (events.isEmpty) const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('当前游戏阶段尚无已发生的切换记录',
            style: TextStyle(fontSize: 12, color: Colors.white70))),
        for (final event in events) Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            const Icon(Icons.timeline, size: 15,
                color: TxTerminalColors.secondaryText),
            const SizedBox(width: 8),
            Expanded(child: Text('${event.symbol}  ·  ${event.label}',
              style: const TextStyle(fontSize: 12))),
            Text('第 ${event.minute} 分钟',
              style: const TextStyle(fontSize: 11,
                color: TxTerminalColors.secondaryText)),
          ])),
      ])));
  }

  void _showMarketEstimate(TxSide side) {
    if (!_ready || _limit) return;
    final quantity = int.tryParse(_qty.text.trim());
    if (quantity == null || quantity < 1 || quantity > TxEngine.maxQuantity) {
      setState(() => _notice = '请先输入有效的市价委托股数');
      return;
    }
    // This is a synchronous read-only preflight against the last durable
    // revision. Trigger only on request, never on a frame or each keystroke.
    final saved = _trader!.current;
    final symbol = _symbolName;
    TxExecutionEstimate estimate;
    try {
      estimate = TxExecutionEstimate.estimate(saved.session.engine,
        ownerId: TxSession.playerId, symbol: symbol,
        side: side, quantity: quantity);
    } catch (e) {
      setState(() => _notice = '市价试算失败，未提交任何订单：$e');
      return;
    }
    if (!mounted) return;
    String price(int? cents) => cents == null ? '—' : '¥${money(cents)}';
    final average = estimate.vwapCents;
    final slippage = estimate.slippageCentsPerShare;
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('${side == TxSide.buy ? '买入' : '卖出'}市价试算 · $symbol'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已提交存档 r${saved.revision} 的盘口快照',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text('申请 $quantity 股 · 预计可成交 ${estimate.executableShares} 股'),
          Text('预计未成交 ${estimate.unfilledShares} 股'),
          Text('预计成交金额 ¥${money(estimate.notionalCents)}'),
          Text('预计成交均价 ${average == null ? '—' : '¥${(average / 100).toStringAsFixed(4)}'}'),
          Text('最优价 ${price(estimate.bestPriceCents)}'
              ' · 最差价 ${price(estimate.worstPriceCents)}'),
          Text('预估滑点 ${slippage == null ? '—' : '${slippage.toStringAsFixed(2)} 分/股'}'),
          if (estimate.rejected) Text('无法执行：${estimate.rejectReason}',
            style: const TextStyle(color: Colors.amberAccent)),
          const SizedBox(height: 8),
          const Text('仅为只读模拟估算；市场流动性、实际资金和'
              '订单簿可能发生变化。未提交订单，未冻结任何资产。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      )),
      actions: [TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('关闭试算'))],
    ));
  }

  // Percentage chips size against available (unreserved) assets. The
  // buy side uses the displayed best ask/limit price as a conservative UI
  // reference, not as a promise of executable market depth or final VWAP.
  void _applyTicketPercent(TxSession session, int percent) {
    if (!_ready) return;
    final account = session.engine.account(TxSession.playerId);
    int maximum;
    if (_ticketSide == TxSide.sell) {
      maximum = TxTicketSizing.maxSellShares(
          account.availableSharesOf(_symbolName));
    } else {
      final asks = session.engine.depth(_symbolName, TxSide.sell);
      final price = _limit ? _cents(_price.text) :
          (asks.isEmpty ? null : asks.first.priceCents);
      maximum = price == null ? 0 : TxTicketSizing.maxBuyShares(
          account.availableCashCents, price);
    }
    if (maximum == 0) {
      setState(() => _notice = '缺少可用资产、有效报价或可用盘口，无法填入比例数量');
      return;
    }
    final amount = TxTicketSizing.percentShares(maximum, percent);
    _qty.text = '$amount';
    if (amount == 0) setState(() =>
        _notice = '可用额度不足 1 股，已填入 0 股；不会自动提交');
  }

  // The compact, tap-to-fill order book is read from verified resting bids
  // and asks. No synthetic quote enters an actual limit ticket.
  Widget _tradeQuickDepth(List<TxBookLevel> bids,
      List<TxBookLevel> asks) {
    Widget column(String title, List<TxBookLevel> levels, Color tint) =>
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: tint,
              fontSize: 12, fontWeight: FontWeight.bold)),
          if (levels.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('暂无挂单', style: TextStyle(fontSize: 11))),
          for (final level in levels.take(5)) InkWell(
            onTap: !_ready ? null : () => setState(() {
              _limit = true;
              _price.text = money(level.priceCents);
            }),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text('¥${money(level.priceCents)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tint, fontSize: 11))),
                Text('${level.quantity}',
                    style: const TextStyle(fontSize: 11,
                        color: Colors.white70)),
              ])),
          ),
        ]));
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('快捷盘口 · 点击价格填入限价',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          column('买盘 Bids', bids, green),
          const SizedBox(width: 14),
          column('卖盘 Asks', asks, red),
        ]),
        const Text('可见委托簿快照，非实时互联网行情。',
            style: TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
    ));
  }

  /// A review is separate from an order. Entering review pauses the visual
  /// clock, and revision + input fields must still match at confirmation.
  void _confirmTicket() {
    if (!_ready) return;
    final quantityText = _qty.text.trim();
    final quantity = int.tryParse(quantityText);
    final limited = _limit;
    final priceText = _price.text.trim();
    final limitPrice = limited ? _cents(priceText) : null;
    if (quantity == null || quantity < 1 || quantity > TxEngine.maxQuantity ||
        (limited && limitPrice == null)) {
      setState(() => _notice = '请检查委托股数及限价；当前输入未产生任何订单');
      return;
    }
    // Stabilize the displayed revision. If any already-running write exists,
    // !_ready guards it above. No next automatic minute begins after pause.
    if (_auto) _pause();
    FocusManager.instance.primaryFocus?.unfocus();
    final revision = _trader!.current.revision;
    final symbol = _symbolName;
    final side = _ticketSide;
    final review = TxTicketReview(revision: revision, symbol: symbol,
        side: side, limited: limited, quantityText: quantityText,
        priceText: priceText);
    final best = _trader!.current.session.engine.depth(symbol,
        side == TxSide.buy ? TxSide.sell : TxSide.buy);
    final referencePrice = limitPrice ??
        (best.isEmpty ? null : best.first.priceCents);
    final indicative = TxTicketSizing.indicativeNotionalCents(
        quantity, referencePrice);
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('确认${side == TxSide.buy ? '买入' : '卖出'} · $symbol'),
      content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(limited ? '委托类型：限价单' : '委托类型：市价单'),
          Text('委托数量：$quantity 股'),
          Text(limited ? '限价：¥${money(limitPrice!)}'
              : '参考盘口价格：${referencePrice == null ? '暂无对手盘' : '¥${money(referencePrice)}'}'),
          Text('参考名义金额：${indicative == null ? '无法估算' : '约 ¥${money(indicative)}'}'),
          Text('存档修订：r$revision'),
          const SizedBox(height: 8),
          const Text('模拟交易：市价单可能跨档滑点或无法全部成交；'
              '限价单可能挂单并冻结资金／持仓。参考价格不是最终成交承诺。',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const Text('确认前行情已暂停；此时尚未提交订单。',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: () {
          Navigator.of(dialogContext).pop();
          if (!mounted) return;
          if (!_ready || !review.isStillCurrent(
              revision: _trader!.current.revision, symbol: _symbolName,
              side: _ticketSide, limited: _limit,
              quantityText: _qty.text.trim(), priceText: _price.text.trim())) {
            setState(() => _notice = '存档修订或下单参数已变化；请重新检查，不执行旧委托');
            return;
          }
          _trade(side);
        }, child: Text('确认${side == TxSide.buy ? '买入' : '卖出'}')),
      ],
    ));
  }

  Widget _trading(TxSession session) {
    final account = session.engine.account(TxSession.playerId);
    final ask = session.engine.depth(_symbolName, TxSide.sell);
    final bid = session.engine.depth(_symbolName, TxSide.buy);
    final active = session.activePlayerOrders;
    // Keep the review button within thumb reach while chart/order ticket
    // content scrolls. During text entry, show the same button in the list
    // instead of covering the Android keyboard.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    Widget reviewButton() => TxTicketSubmitBar(side: _ticketSide,
        isLimit: _limit, enabled: _ready, onReview: _confirmTicket);
    return Column(children: [
      Expanded(child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14), children: [
      _title('交易委托', sub: '市价可能跨档滑点；真实资金/库存限制'),
      _chooseSymbol(session),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        SizedBox(width: double.infinity, child: SegmentedButton<TxSide>(
          segments: const [
            ButtonSegment(value: TxSide.buy, label: Text('买入 Buy'),
                icon: Icon(Icons.trending_up)),
            ButtonSegment(value: TxSide.sell, label: Text('卖出 Sell'),
                icon: Icon(Icons.trending_down)),
          ], selected: {_ticketSide},
          onSelectionChanged: !_ready ? null :
              (selected) => setState(() => _ticketSide = selected.first))),
        const SizedBox(height: 12),
        Wrap(children: [
          _metric('可用资金', '¥${money(account.availableCashCents)}'),
          _metric('可卖数量', '${account.availableSharesOf(_symbolName)} 股'),
          _metric('卖一', ask.isEmpty ? '—' : '¥${money(ask.first.priceCents)}'),
          _metric('买一', bid.isEmpty ? '—' : '¥${money(bid.first.priceCents)}'),
        ]),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('市价 Market'),
                icon: Icon(Icons.bolt_outlined)),
            ButtonSegment(value: true, label: Text('限价 Limit'),
                icon: Icon(Icons.tune)),
          ], selected: {_limit},
          onSelectionChanged: !_ready ? null :
              (values) => setState(() => _limit = values.first))),
        if (_limit) Wrap(spacing: 6, children: [
          ActionChip(label: const Text('卖一价'),
            onPressed: ask.isEmpty || !_ready ? null : () =>
                _price.text = money(ask.first.priceCents)),
          ActionChip(label: const Text('买一价'),
            onPressed: bid.isEmpty || !_ready ? null : () =>
                _price.text = money(bid.first.priceCents)),
        ]),
        const Align(alignment: Alignment.centerLeft,
            child: Text('快捷数量', style: TextStyle(color: Colors.white70))),
        Wrap(spacing: 5, runSpacing: 0, children: [
          for (final amount in [1, 10, 100, 500])
            ActionChip(label: Text('$amount股'),
              onPressed: _ready ? () => _qty.text = '$amount' : null),
        ]),
        const SizedBox(height: 5),
        const Align(alignment: Alignment.centerLeft,
            child: Text('使用可用资产比例 · 参考价估算',
              style: TextStyle(color: Colors.white70, fontSize: 12))),
        Wrap(spacing: 5, children: [
          for (final percent in [25, 50, 75, 100])
            ActionChip(label: Text('$percent%'),
              onPressed: !_ready ? null :
                  () => _applyTicketPercent(session, percent)),
        ]),
        const SizedBox(height: 6),
        TextField(controller: _qty, enabled: _ready,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '委托股数',
              border: OutlineInputBorder())),
        if (_limit) ...[
          const SizedBox(height: 10),
          TextField(controller: _price, enabled: _ready,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '限价 ¥',
                border: OutlineInputBorder())),
        ],
        const SizedBox(height: 8),
        ListenableBuilder(listenable: Listenable.merge([_qty, _price]),
          builder: (context, child) {
            final qty = int.tryParse(_qty.text.trim()) ?? 0;
            final quoted = _limit ? _cents(_price.text) :
                (_ticketSide == TxSide.buy ?
                    (ask.isEmpty ? null : ask.first.priceCents) :
                    (bid.isEmpty ? null : bid.first.priceCents));
            final ref = TxTicketSizing.indicativeNotionalCents(qty, quoted);
            return Align(alignment: Alignment.centerLeft,
              child: Text('参考名义金额：${ref == null ? '—' : '约 ¥${money(ref)}'}'
                ' · ${_limit ? '以限价计算' : '按最优档价格估算，实际可能滑点'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)));
          }),
        const SizedBox(height: 12),
        if (!_limit) ...[
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _ready ? () => _showMarketEstimate(TxSide.buy) : null,
              icon: const Icon(Icons.calculate_outlined, size: 17),
              label: const Text('试算买入'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _ready ? () => _showMarketEstimate(TxSide.sell) : null,
              icon: const Icon(Icons.calculate_outlined, size: 17),
              label: const Text('试算卖出'))),
          ]),
          const SizedBox(height: 6),
          const Text('试算不会冻结资金或提交订单；实时价格可能变化。',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 12),
        ],
        if (keyboardOpen) reviewButton(),
      ]))),
      if (active.isEmpty) const ListTile(
          dense: true, title: Text('暂无活动委托')),
      if (active.isNotEmpty) Card(child: ExpansionTile(
        title: Text('活动委托（${active.length}）'),
        subtitle: const Text('点击展开查看挂单与撤单'),
        children: [for (final order in active) ListTile(
          title: Text('${order.symbol} · ${order.side==TxSide.buy?'买':'卖'} '
              '${order.remaining}/${order.quantity}股'),
          subtitle: Text('${order.id} · ¥${money(order.limitPriceCents!)}'),
          trailing: IconButton(tooltip: '撤单',
            icon: const Icon(Icons.close),
            onPressed: _ready ? () => _cancel(order.id) : null),
        )],
      )),
      _tradeQuickDepth(bid, ask),
    ])),
    if (!keyboardOpen) reviewButton(),
    ]);
  }

  Map<String, TxPosition> _positionsForRevision(
      TxSession session, int revision) {
    if (_positionCache == null || _positionCacheRevision != revision) {
      _positionCache = TxPositionAnalytics.compute(session);
      _positionCacheRevision = revision;
    }
    return _positionCache!;
  }

  TxTradeJournal _journalForRevision(TxSession session,int revision) {
    if(_journalCacheRevision!=revision || _journalCache==null) {
      _journalCache=TxTradeJournal.compute(session);
      _journalCacheRevision=revision;
    }
    return _journalCache!;
  }

  Widget _riskRatio(String title, double fraction) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 12)),
        Text('${(fraction * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: fraction.clamp(0.0, 1.0).toDouble(),
          minHeight: 5, backgroundColor: const Color(0xFF293448)),
    ]),
  );

  Widget _assets(TxSession session, TxStoredSession saved) {
    final account = session.engine.account(TxSession.playerId);
    final holdings = _positionsForRevision(session, saved.revision);
    final risk = TxPortfolioRisk.compute(session);
    final reliable = holdings.values.every((p) => p.costKnown);
    final unrealized = holdings.values.fold<int>(0,
        (total, p) => total + p.unrealizedPnlCents);
    final realized = holdings.values.fold<int>(0,
        (total, p) => total + p.realizedPnlCents);
    Widget pnlValue(String label, int amount) =>
      _metric(label, signedMoney(amount));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _title('资金与资产', sub: '估值随分时指示价连续变动；现金与已实现收益只按真实成交结算'),
      ValueListenableBuilder<double>(valueListenable: _seconds,
        builder: (context, seconds, _) {
          final mark = TxLivePortfolioValuation.evaluate(
              session, holdings, seconds);
          return Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Wrap(children: [
              _metric('实时预估总资产', '¥${money(mark.totalAssetsCents)}'),
              _metric('现金余额', '¥${money(account.cashCents)}'),
              _metric('可用现金', '¥${money(account.availableCashCents)}'),
              _metric('冻结资金', '¥${money(account.reservedCashCents)}'),
              if (mark.unrealizedPnlCents != null)
                pnlValue('实时预估浮动盈亏', mark.unrealizedPnlCents!),
              if (reliable) pnlValue('累计已实现盈亏', realized),
          ])));
        }),
      _title('仓位风险仪表盘', sub: '仅分析已提交资产；参考阈值用于模拟游戏，不发出交易指令'),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('股票市值 ¥${money(risk.investedCents)} · '
              '可用现金 ¥${money(risk.availableCashCents)}'),
          const SizedBox(height: 8),
          _riskRatio('股票仓位占总资产', risk.investedFraction),
          _riskRatio('可用现金占总资产', risk.availableCashFraction),
          _riskRatio('最大标的占股票仓位', risk.largestPositionFraction),
          if (risk.largestSymbol != null) Text(
            '最大持仓：${risk.largestSymbol}（按已提交参考价估值）',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (risk.highConcentration)
            const Text('提示：单一标的占股票市值至少 75%，持仓较集中',
                style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
          if (risk.lowLiquidity)
            const Text('提示：可用现金低于总资产的 10%，新买单流动性较低',
                style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
          if (risk.investedCents == 0)
            const Text('当前没有股票持仓；现金比例仍受冻结买单影响',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
        ]))),
      _title('资产压力测试', sub:'假设所有模拟标的同时变动；只读估值，不会触发交易'),
      Card(child:Padding(padding:const EdgeInsets.all(14),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          for(final shock in [-500,-1000,-2000]) Builder(
            builder:(context) {
              final scenario=TxPortfolioScenarios.evaluate(session,shock);
              return Padding(padding:const EdgeInsets.symmetric(vertical:5),
                child:Row(children:[
                  SizedBox(width:66,child:Text('${shock~/100}%',
                    style:const TextStyle(fontWeight:FontWeight.w700))),
                  Expanded(child:Text('总资产 ¥${money(scenario.projectedAssetsCents)}',
                    style:const TextStyle(fontSize:12))),
                  Text(signedMoney(scenario.changeCents),
                    style:TextStyle(fontSize:12,color:
                      scenario.changeCents<0?red:green)),
                ]));
            }),
          const SizedBox(height:5),
          const Text('仅重估已提交持仓；现金和冻结资产不变，'
            '不预测未来、也不会触发止损或任何订单。',
            style:TextStyle(fontSize:11,color:Colors.white54)),
        ]))),
      _title('持仓成本与收益', sub: '移动加权平均成本，卖出按平均成本确认已实现收益'),
      for (final symbol in TxSession.symbols)
        Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('持有 ${account.sharesOf(symbol)} 股 · 可卖 '
              '${account.availableSharesOf(symbol)} 股 · 冻结 '
              '${account.reservedSharesOf(symbol)} 股'),
          const SizedBox(height: 4),
          if (holdings[symbol]!.costKnown) ...[
            Text('平均成本 ¥${(holdings[symbol]!.averagePriceCents/100).toStringAsFixed(4)} '
                '· 持仓成本 ¥${money(holdings[symbol]!.costBasisCents)}'),
            ValueListenableBuilder<double>(valueListenable: _seconds,
              builder: (context, seconds, _) {
                final mark = TxLivePortfolioValuation.evaluate(
                    session, holdings, seconds);
                final market = mark.marketValuesCents[symbol]!;
                final basis = holdings[symbol]!.costBasisCents;
                final floatPnl = market - basis;
                final percent = basis <= 0 ? 0.0 : floatPnl * 100 / basis;
                return Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text('实时指示价 ¥${money(mark.pricesCents[symbol]!)} '
                      '· 预估市值 ¥${money(market)}'),
                  Text('预估浮动盈亏 ${signedMoney(floatPnl)} '
                      '(${percent.toStringAsFixed(2)}%)',
                      style: TextStyle(color: floatPnl >= 0 ? green : red)),
                ]);
              }),
            Text('累计已实现 ${signedMoney(holdings[symbol]!.realizedPnlCents)}'),
          ] else const Text('历史库存与成交记录不完整，成本/收益暂不可核算',
              style: TextStyle(color: Colors.amberAccent)),
          Align(alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => setState(() {
                _symbol = TxSession.symbols.indexOf(symbol);
                _limit = false;
                _page = 1;
              }), child: const Text('交易此标的 →'))),
        ]))),
      _title('存档周期设置', sub: '控制完整检查点的频率，不会延迟交易或分钟提交'),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('当前：每 $_checkpointInterval 次成功提交生成完整检查点',
            style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('选择：每 $_checkpointDraft 次提交',
            style: const TextStyle(color: TxTerminalColors.secondaryText)),
          Row(children: [
            IconButton(tooltip: '减少一次', icon: const Icon(Icons.remove_circle_outline),
              onPressed: _ready && _checkpointDraft > 1
                ? () => setState(() => _checkpointDraft--) : null),
            Expanded(child: Slider(
              min: 1, max: TxDeltaCodec.maxCheckpointInterval.toDouble(),
              divisions: TxDeltaCodec.maxCheckpointInterval - 1,
              value: _checkpointDraft.toDouble(),
              label: '$_checkpointDraft',
              onChanged: _ready
                ? (v) => setState(() => _checkpointDraft = v.round()) : null,
            )),
            IconButton(tooltip: '增加一次', icon: const Icon(Icons.add_circle_outline),
              onPressed: _ready &&
                  _checkpointDraft < TxDeltaCodec.maxCheckpointInterval
                ? () => setState(() => _checkpointDraft++) : null),
          ]),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final count in const [8, 16, 32, 64])
              ChoiceChip(label: Text('$count 次'),
                selected: _checkpointDraft == count,
                onSelected: _ready
                  ? (_) => setState(() => _checkpointDraft = count) : null),
          ]),
          const SizedBox(height: 9),
          FilledButton.icon(onPressed: _ready &&
              _checkpointDraft != _checkpointInterval
                ? _saveCheckpointInterval : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存检查点周期')),
          const SizedBox(height: 6),
          const Text('建议 32 次（默认）。较短间隔恢复更快，但完整存档更多；'
            '较长间隔可能节省空间，恢复时需要回放更多增量。'
            '为保证安全，每 64 次提交仍强制生成完整检查点。'
            '本设置不是每隔若干分钟才存钱，所有真实交易均立即原子提交。',
            style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]))),
      _title('存档状态'),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('修订 ${saved.revision} · 模拟步数 ${session.step}'),
          ValueListenableBuilder<double>(valueListenable: _seconds,
            builder: (context, second, child) => Text(
              '第 ${TxRealtimeClock.gameDay(session.step, second.floor())} 天 '
              '${TxRealtimeClock.hhmmss(session.step, second.floor())}')),
          Text('校验 ${saved.sha256.substring(0,16)}…'),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _ready ? _inspectStorage : null,
              icon: const Icon(Icons.storage, size: 16),
              label: const Text('查看数据库占用'))),
          if (_storageFootprint != null) ...[
            Text('诊断采样 r${_storageFootprint!.revision}'
              '${_storageFootprint!.revision == saved.revision ? '' : ' · 已过期，请重新读取'}',
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
            Text('SQLite 约 ${_storageFootprint!.databaseMiB.toStringAsFixed(2)} MiB'
              ' · 历史快照 ${_storageFootprint!.snapshotCount} 份',
              style: const TextStyle(fontSize: 12)),
            Text('最新存储记录 ${_storageFootprint!.latestSnapshotKiB.toStringAsFixed(1)} KiB'
              '（TXD1 增量记录 / TXZ1 完整检查点，数据只读统计）',
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
            if (_storageFootprint!.largeDatabase)
              const Text('数据库超过 100 MiB；请勿删除旧快照。',
                style: TextStyle(fontSize: 11, color: Colors.amberAccent)),
          ],
        ],
      ))),
    ]);
  }

  String _participantLabel(String accountId) {
    if (accountId == TxSession.playerId) return '玩家';
    if (accountId.startsWith('LP_')) return '做市商 $accountId';
    if (accountId.startsWith('NPC_')) return '模拟交易者 ${accountId.substring(4)}';
    return accountId;
  }

  Widget _marketTape(TxSession session) {
    final total = session.engine.fillCount;
    final shown = TxMarketTapeWindow.visibleCount(
        total, _marketTapeRequested);
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('市场真实逐笔', sub: '默认最新 24 条，按需显示；历史成交及资金账本永久保留'),
            SingleChildScrollView(scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(segments: const [
                ButtonSegment(value: 0, label: Text('我的委托')),
                ButtonSegment(value: 1, label: Text('我的成交')),
                ButtonSegment(value: 2, label: Text('市场逐笔')),
                ButtonSegment(value: 3, label: Text('交易复盘')),
              ], selected: {_recordMode}, onSelectionChanged: (v) =>
                  setState(() => _recordMode = v.first))),
            Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('显示最近 $shown / $total 笔真实成交 · 列表按需绘制',
                style: const TextStyle(color: Colors.white60, fontSize: 12))),
          ])),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        itemCount: shown == 0 ? 1 : shown +
            (shown < total && shown < TxMarketTapeWindow.maximum ? 1 : 0),
        itemBuilder: (context, index) {
          if (shown == 0) {
            return const ListTile(title: Text('市场尚无实际成交'));
          }
          if (index == shown) {
            return TextButton(
              onPressed: () => setState(() => _marketTapeRequested =
                  TxMarketTapeWindow.expand(_marketTapeRequested)),
              child: const Text('加载更早的 24 条'));
          }
          final f = session.engine.fillAt(
              TxMarketTapeWindow.newestFirstFillIndex(total, index));
          return Card(child: ListTile(dense: true,
            title: Text('${f.id} ${f.symbol} ${f.quantity}股'),
            subtitle: Text('${_participantLabel(session.engine.order(f.buyOrderId).ownerId)} 买'
                ' ← ${_participantLabel(session.engine.order(f.sellOrderId).ownerId)} 卖'),
            trailing: Text('¥${money(f.priceCents)}')));
        },
      )),
    ]);
  }

  Widget _records(TxSession session) {
    if (_recordMode == 2) return _marketTape(session);
    // Only prepare the visible tab. In particular, opening the orders tab
    // must not walk the entire ever-growing market fill history.
    final orders = _recordMode == 0
        ? session.recentPlayerOrders(limit: 100) : const <TxOrder>[];
    final playerFills = _recordMode == 1
        ? session.recentPlayerFills(limit: 100) : const <TxFill>[];
    final journal = _recordMode == 3
        ? _journalForRevision(session,_trader!.current.revision) : null;
    return ListView(padding: const EdgeInsets.all(14), children: [
      _title('真实成交与交易复盘', sub: '委托与逐笔展示最近 100 条；复盘汇总全部已提交成交'),
      SingleChildScrollView(scrollDirection:Axis.horizontal,
        child:SegmentedButton<int>(segments: const [
        ButtonSegment(value: 0, label: Text('我的委托')),
        ButtonSegment(value: 1, label: Text('我的成交')),
        ButtonSegment(value: 2, label: Text('市场逐笔')),
        ButtonSegment(value: 3, label: Text('交易复盘')),
      ], selected: {_recordMode},
        onSelectionChanged: (v) => setState(() => _recordMode = v.first))),
      if (_recordMode == 3 && journal != null) ...[
        Card(child:Padding(padding:const EdgeInsets.all(14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('成交账簿复盘',style:TextStyle(fontWeight:FontWeight.bold)),
            const SizedBox(height:8),
            Text('真实买入：${journal.buyFills} 笔 / ${journal.boughtShares} 股'
                 ' · ¥${money(journal.buyNotionalCents)}'),
            Text('真实卖出：${journal.sellFills} 笔 / ${journal.soldShares} 股'
                 ' · ¥${money(journal.sellNotionalCents)}'),
            if(journal.costKnown) ...[
              Text('累计已实现 ${signedMoney(journal.realizedCents!)}'),
              Text('已匹配卖出成交 ${journal.closedFills} 笔'
                ' · 盈利 ${journal.winningCloses} / 亏损 ${journal.losingCloses}'),
              Text(journal.winRate==null ? '盈利成交占比：暂无卖出' :
                '盈利成交占比：${(journal.winRate!*100).toStringAsFixed(1)}%'),
            ] else const Text('成本来源不完整：无法核算可靠盈亏或胜率',
              style:TextStyle(color:Colors.amberAccent,fontSize:12)),
            const SizedBox(height:5),
            const Text('每笔卖出撮合按加权平均成本判断；'
              '盈利成交占比不代表整单胜率，也不计未成交委托。',
              style:TextStyle(color:Colors.white54,fontSize:11)),
          ]))),
        if(journal.costKnown) for(final close in journal.recentCloses)
          Card(child:ListTile(dense:true,
            title:Text('${close.symbol} · 卖出 ${close.quantity} 股'),
            subtitle:Text(close.fillId),
            trailing:Text(signedMoney(close.realizedCents),
              style:TextStyle(color:close.realizedCents>=0?green:red)))),
        if(journal.sellFills==0) const ListTile(title:Text('暂无已卖出成交')),
      ],
      if (_recordMode == 0 && orders.isEmpty)
        const ListTile(title: Text('暂无个人委托')),
      if (_recordMode == 1 && playerFills.isEmpty)
        const ListTile(title: Text('暂无个人成交')),
      if (_recordMode == 0) for (final order in orders)
        Card(child: ListTile(dense: true,
          title: Text('${order.id} ${order.symbol} '
              '${order.side == TxSide.buy ? '买' : '卖'}'),
          subtitle: Text('${order.status.name} · '
              '成交${order.filled} · 余${order.remaining}'),
          trailing: Text(order.limitPriceCents == null ? '市价' :
              '¥${money(order.limitPriceCents!)}'))),
      if (_recordMode == 1) for (final f in playerFills)
        Card(child: ListTile(dense: true,
          title: Text('${f.id} ${f.symbol} ${f.quantity}股'),
          subtitle: Text(session.engine.order(f.buyOrderId).ownerId ==
              TxSession.playerId ? '玩家买入' : '玩家卖出'),
          trailing: Text('¥${money(f.priceCents)}'))),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackTicker.dispose();
    _seconds.dispose();
    _qty.dispose();
    _price.dispose();
    final work = _operation;
    if (work == null) {
      _trader?.close();
    } else {
      work.whenComplete(() async => _trader?.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: SafeArea(child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('TERMINAL X', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 26, letterSpacing: 4)),
          SizedBox(height: 20),
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('正在后台校验存档并恢复行情…',
              style: TextStyle(color: Colors.white70)),
        ]))));
    if (_trader == null) return Scaffold(appBar: AppBar(
      title: const Text('Terminal X · 存档保护')),
      body: Padding(padding: const EdgeInsets.all(18),
        child: SelectableText(_fault ?? '存档读取失败')));

    final stored = _trader!.current;
    final session = stored.session;
    return Scaffold(
      appBar: AppBar(title: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TERMINAL  X', style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 1.5)),
          Text('v$appVersion  ·  本地模拟市场', style: const TextStyle(
            fontSize: 10, color: TxTerminalColors.secondaryText)),
        ]), actions: [
          IconButton(tooltip: _auto ? '暂停' : '运行',
              onPressed: (_auto || _ready) ? _toggle : null,
              icon: Icon(_auto ? Icons.pause_circle : Icons.play_circle_outline)),
        ]),
      body: Column(children: [
        TxTerminalStatus(seconds: _seconds, step: session.step,
          revision: stored.revision, running: _auto,
          speed: _speed, busy: _busy),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_fault != null) Padding(padding: const EdgeInsets.all(10),
            child: SelectableText(_fault!, style: const TextStyle(color: red))),
        if (_fault == null) Padding(padding: const EdgeInsets.all(8),
          child: Text(_notice, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12))),
        Expanded(child: switch (_page) {
          0 => _market(session),
          1 => _trading(session),
          2 => _assets(session, stored),
          _ => _records(session),
        }),
      ]),
      // The system keyboard takes priority over bottom navigation.
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
        ? null : NavigationBar(selectedIndex: _page,
        onDestinationSelected: (i) => setState(() => _page=i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.candlestick_chart), label: '行情'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: '交易'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: '资产'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: '记录'),
        ]),
    );
  }
}
