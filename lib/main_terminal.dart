/// Terminal X 0.4.0 unified trading interface and market-structure analytics.
/// Existing V0.2 + V0.1 apps and backups are never accessed.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
import 'market/tx_market_phase_timeline.dart';
import 'market/tx_market_profiles.dart';
import 'market/tx_market_session_schedule.dart';
import 'market/tx_market_conditional_orders.dart';
import 'market/tx_independent_market_service.dart';
import 'market/tx_market_microstructure.dart';
import 'market/tx_market_risk_core.dart';
import 'market/tx_market_venue.dart';
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
import 'widgets/tx_market_ecosystem_card.dart';
import 'widgets/tx_back_exit_guard.dart';
import 'widgets/tx_settings_page.dart';
import 'widgets/tx_premium_ui.dart';

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

class _TxChartOverlayPrefs {
  bool showCost = true;
  bool showBreakeven = true;
  bool showLiquidation = true;
}

class _TxConditionalDraft {
  const _TxConditionalDraft({
    required this.kind,
    required this.triggerPriceCents,
    required this.quantity,
  });

  final TxMarketConditionalOrderKind kind;
  final int triggerPriceCents;
  final int quantity;
}

class _TerminalHomeV024State extends State<TerminalHomeV024>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const green = TxTerminalColors.buy;
  static const red = TxTerminalColors.sell;
  static const appVersion = String.fromEnvironment('TX_APP_VERSION', defaultValue: '0.4.0');
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController(text: '10.00');
  TxTradingService? _trader;
  TxIndependentMarketService? _independentMarkets;
  TxLiveCandles? _candles;
  late final Ticker _playbackTicker;
  Duration? _previousFrame;
  final TxContinuousFlowClock _flow = TxContinuousFlowClock(pulseSeconds: 15);
  final TxCommittedSpeedWindow _committedSpeed = TxCommittedSpeedWindow();
  final Stopwatch _speedStopwatch = Stopwatch();
  final TxCommitLatencyWindow _commitLatency = TxCommitLatencyWindow();
  final TxCommitLatencyWindow _pulseLatency = TxCommitLatencyWindow();
  final TxCommitLatencyWindow _marketLatency = TxCommitLatencyWindow();
  final TxCommitLatencyWindow _sqliteLatency = TxCommitLatencyWindow();
  final TxFrameRenderGate _frameRenderGate = TxFrameRenderGate();
  // Keep chart/hero motion in a repaint island. High multipliers may update
  // this notifier without rebuilding the status strip or scroll layout.
  final TxFrameRenderGate _chartFrameRenderGate = TxFrameRenderGate(
      minimumInterval: Duration(milliseconds: 33));
  TxStorageFootprint? _storageFootprint;
  int _checkpointInterval = TxDeltaCodec.checkpointInterval;
  int _checkpointDraft = TxDeltaCodec.checkpointInterval;
  int? _positionCacheRevision;
  Map<String, TxPosition>? _positionCache;
  int? _journalCacheRevision;
  TxTradeJournal? _journalCache;
  Future<void>? _operation;
  Future<void>? _backgroundFlush;
  int _page = 0;
  int _symbol = 0;
  TxMarketMode _marketMode = TxMarketMode.aShare;
  int _speed = 1;
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _chartSeconds = ValueNotifier<double>(0.0);
  // Authoritative provisional time used for market gates and independent
  // board synchronization. At high multipliers the public display is held at
  // the last safe boundary so the whole scroll view does not repaint for
  // every large seconds jump.
  double _clockSeconds = 0.0;
  final ValueNotifier<int> _marketRepaint = ValueNotifier<int>(0);
  final ValueNotifier<bool> _settling = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _pulseSettling = ValueNotifier<bool>(false);
  final ValueNotifier<double> _settlementPhase = ValueNotifier<double>(0.0);
  bool _auto = false;
  bool _busy = false;
  bool _loading = true;
  bool _historyWarming = false;
  bool _limit = false;
  TxTimeInForce _timeInForce = TxTimeInForce.gtc;
  TxSide _ticketSide = TxSide.buy;
  int _recordMode = 0;
  int _marketTapeRequested = TxMarketTapeWindow.pageSize;
  int _automaticSaveMinutes = TxSqliteStore.defaultAutomaticSaveMinutes;
  int _automaticSaveDraft = TxSqliteStore.defaultAutomaticSaveMinutes;
  String _notice = '正在检查 SQLite';
  String? _fault;
  String _rustStatus = '等待 Rust 核心';
  final Stopwatch _startupStopwatch = Stopwatch();
  Timer? _startupTimer;
  Duration _startupElapsed = Duration.zero;
  double _startupProgress = .02;
  String _startupStage = '准备启动 Terminal X';
  Future<void>? _candleWarmup;
  bool _serviceClosed = false;
  bool _recoveringStorage = false;
  Future<void>? _recoveryOperation;
  bool _independentLoading = false;
  String? _independentFault;
  bool _cancelIndependentPrewarm = false;
  Future<void>? _independentPrewarm;
  final Map<String, _TxChartOverlayPrefs> _chartOverlayPrefs = {};
  bool _reduceOnly = false;

  bool get _ready => !_loading && !_busy && _fault == null &&
      !_historyWarming &&
      _trader != null && !_trader!.blocked;
  bool get _independentMode => _marketMode != TxMarketMode.aShare;
  TxIndependentMarketState? get _independentState =>
      _independentMarkets?.state(_marketMode);
  bool get _tradingReady => _ready &&
      (!_independentMode && _marketMode == TxMarketMode.aShare ||
          _independentMode && !_independentLoading &&
              _independentState != null && _independentFault == null);
  String get _symbolName => TxSession.symbols[_symbol];
  String money(int cents) => (cents / 100).toStringAsFixed(2);
  String signedMoney(int cents) => '${cents >= 0 ? '+' : '-'}¥${money(cents.abs())}';
  double _indication(TxSession session, double seconds) => TxFrameQuote.cents(
      session.lastPrice(_symbolName), session.step, seconds, _symbol);

  bool _marketPreviewAllowed(TxSession session, double seconds) {
    final fractionalSeconds = seconds.floor().clamp(0, 59).toInt();
    final status = TxSession.marketSessionStatusAt(
        committedStep: session.step,
        fractionalSeconds: fractionalSeconds);
    // The status strip is deliberately throttled at high speed, but the
    // chart/hero use their own bounded repaint notifier. Keep the indicative
    // quote available there so high speed no longer looks frozen.
    if (!status.isOpen) return false;
    return _auto || seconds > 0;
  }

  double _displayIndication(TxSession session, double seconds) =>
      _marketPreviewAllowed(session, seconds)
          ? _indication(session, seconds)
          : session.lastPrice(_symbolName).toDouble();

  /// Independent venues have a durable mark only at their game-minute
  /// boundary.  Use the same explicitly-labelled, non-traded frame quote as
  /// A-share for the seconds between two boundaries; otherwise an independent
  /// chart can only change after a real fill and appears frozen even while its
  /// mark, book and participants are alive.
  bool _independentPreviewAllowed(TxIndependentMarketState state,
      TxSession session, double seconds) {
    if (!seconds.isFinite || seconds < 0 || seconds >= 60) {
      return false;
    }
    final status = state.profile.schedule.status(
        gameDay: _clockGameDay(session),
        minuteOfDay: _clockMinuteOfDay(session));
    return status.isOpen && (_auto || seconds > 0);
  }

  double _independentIndicativePrice(TxIndependentMarketState state,
      TxSession session, String symbol, double seconds) {
    final mark = state.markPriceCents(symbol);
    if (!_independentPreviewAllowed(state, session, seconds)) {
      return mark.toDouble();
    }
    final symbolIndex = state.profile.instruments.indexWhere(
        (instrument) => instrument.symbol == symbol);
    // The mode offset keeps two independent boards from sharing an identical
    // optical phase. This is a display-only quote and never creates a fill,
    // volume row or SQLite revision.
    return TxFrameQuote.cents(
        mark, _independentTimeStep(state), seconds,
        math.max(0, symbolIndex) + state.mode.index * 3);
  }

  int _clockGameDay(TxSession session) => TxRealtimeClock.gameDay(
      session.step, _clockSeconds.floor().clamp(0, 59).toInt());

  int _clockMinuteOfDay(TxSession session) => TxRealtimeClock.gameMinuteOfDay(
      session.step, _clockSeconds.floor().clamp(0, 59).toInt());

  TxMarketSessionStatus _selectedSessionStatus(TxSession session) {
    final profile = TxMarketProfile.of(_marketMode);
    return profile.schedule.status(
        gameDay: _clockGameDay(session),
        minuteOfDay: _clockMinuteOfDay(session));
  }

  int _independentTimeStep(TxIndependentMarketState state) =>
      (state.runtime.gameDay - 1) * 1440 + state.runtime.minuteOfDay;

  int _independentSessionStep(TxIndependentMarketState state) => math.max(
      0, _independentTimeStep(state) - TxRealtimeClock.firstMinuteOfDay);

  String _quotePrice(TxMarketProfile profile, int cents) {
    final prefix = switch (profile.quoteCurrency) {
      'CNY' => '¥',
      'USD' => '\$',
      'USDT' => '₮',
      _ => '${profile.quoteCurrency} ',
    };
    final decimals = profile.mode == TxMarketMode.forex ? 4 : 2;
    return '$prefix${(cents / 100).toStringAsFixed(decimals)}';
  }

  String _quoteAmount(TxMarketProfile profile, int cents) => cents < 0
      ? '-${_quotePrice(profile, cents.abs())}'
      : _quotePrice(profile, cents);

  String _deskCompact(int value) {
    final absolute = value.abs();
    if (absolute >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}m';
    }
    if (absolute >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return '$value';
  }

  String _deskChange(TxMarketProfile profile, int deltaCents) {
    if (deltaCents == 0) return '—';
    final sign = deltaCents > 0 ? '+' : '-';
    return '$sign${_quotePrice(profile, deltaCents.abs())}';
  }

  Color _deskStatusColor(TxMarketSessionStatus status) => switch (status.state) {
    TxMarketSessionState.open => TxTerminalColors.buy,
    TxMarketSessionState.breakTime => TxTerminalColors.gold,
    TxMarketSessionState.closed => TxTerminalColors.secondaryText,
  };

  TxMarketDeskQuote _aShareDeskQuote(TxSession session,
      TxMarketProfile profile, int gameDay, int minuteOfDay) {
    final symbol = _marketMode == TxMarketMode.aShare
        ? _symbolName : TxSession.symbols.first;
    final status = profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    final candles = _candles?.forSymbol(symbol) ?? const [];
    final price = session.lastPrice(symbol);
    final reference = candles.length >= 2
        ? candles[candles.length - 2].closeCents
        : candles.isEmpty ? price : candles.last.openCents;
    final delta = price - reference;
    final fills = session.currentMinuteFills
        .where((fill) => fill.symbol == symbol).toList();
    final volume = fills.fold<int>(0, (sum, fill) => sum + fill.quantity);
    final bids = session.engine.depth(symbol, TxSide.buy, levels: 10);
    final asks = session.engine.depth(symbol, TxSide.sell, levels: 10);
    final depth = [...bids, ...asks].fold<int>(
        0, (sum, level) => sum + level.quantity);
    final account = session.engine.account(TxSession.playerId);
    return TxMarketDeskQuote(
      mode: profile.mode,
      label: profile.label,
      symbol: symbol,
      status: status.label,
      mark: _quotePrice(profile, price),
      change: _deskChange(profile, delta),
      activity: '${fills.length} 笔 · ${_deskCompact(volume)}${profile.orderUnit}',
      liquidity: '深 ${_deskCompact(depth)}',
      account: _quoteAmount(profile, account.availableCashCents),
      isOpen: status.isOpen,
      isLoaded: true,
      isSelected: _marketMode == profile.mode,
      accent: _deskStatusColor(status),
      pressure: TxOrderBookInsight.fromLevels(bids: bids, asks: asks)
          .bidShareFraction,
    );
  }

  TxMarketDeskQuote _independentDeskQuote(TxSession session,
      TxMarketProfile profile, int gameDay, int minuteOfDay) {
    final state = _independentMarkets?.state(profile.mode);
    final scheduleStatus = profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    if (state == null) {
      return TxMarketDeskQuote(
        mode: profile.mode,
        label: profile.label,
        symbol: profile.instruments.first.symbol,
        status: scheduleStatus.isOpen ? '待打开 · ${scheduleStatus.label}'
            : scheduleStatus.label,
        mark: '—',
        change: '—',
        activity: '待打开',
        liquidity: '未载入',
        account: '未载入',
        isOpen: scheduleStatus.isOpen,
        isLoaded: false,
        isSelected: _marketMode == profile.mode,
        accent: _deskStatusColor(scheduleStatus),
      );
    }
    final status = state.sessionStatus;
    final symbol = profile.instruments.first.symbol;
    final candles = state.candlesFor(symbol);
    final mark = state.markPriceCents(symbol);
    final reference = candles.length >= 2
        ? candles[candles.length - 2].closeCents
        : candles.isEmpty ? mark : candles.last.openCents;
    final delta = mark - reference;
    final fills = state.runtime.venue.fillsForMinute(
        state.runtime.gameDay, state.runtime.minuteOfDay, symbol: symbol);
    final volume = fills.fold<int>(0, (sum, fill) => sum + fill.quantity);
    final fillCount = fills.length;
    final bids = state.runtime.venue.depth(symbol, TxSide.buy, levels: 10);
    final asks = state.runtime.venue.depth(symbol, TxSide.sell, levels: 10);
    final depth = [...bids, ...asks].fold<int>(
        0, (sum, level) => sum + level.quantity);
    final stats = state.runtime.venue.stats;
    final risk = state.playerRisk;
    return TxMarketDeskQuote(
      mode: profile.mode,
      label: profile.label,
      symbol: symbol,
      status: status.label,
      mark: _quotePrice(profile, mark),
      change: _deskChange(profile, delta),
      activity: '$fillCount 笔 · ${_deskCompact(volume)}${profile.orderUnit}',
      liquidity: '深 ${_deskCompact(depth)} · ${stats.activeOrders}单',
      account: _quoteAmount(profile, risk.equityCents),
      isOpen: status.isOpen,
      isLoaded: true,
      isSelected: _marketMode == profile.mode,
      accent: _deskStatusColor(status),
      pressure: TxOrderBookInsight.fromLevels(bids: bids, asks: asks)
          .bidShareFraction,
    );
  }

  List<TxMarketDeskQuote> _marketDeskQuotes(TxSession session) {
    final gameDay = _clockGameDay(session);
    final minuteOfDay = _clockMinuteOfDay(session);
    return [
      _aShareDeskQuote(session, TxMarketProfile.aShare,
          gameDay, minuteOfDay),
      for (final profile in TxMarketProfile.values.skip(1))
        _independentDeskQuote(session, profile, gameDay, minuteOfDay),
    ];
  }

  Widget _marketDeskOverview(TxSession session) => TxMarketDeskOverview(
    quotes: _marketDeskQuotes(session),
    onSelected: (mode) => unawaited(_selectMarketMode(mode, session)),
  );

  TxMarketAggressor _aggressorForOrders({required int buySequence,
      required int sellSequence}) {
    if (buySequence == sellSequence) return TxMarketAggressor.unknown;
    return buySequence > sellSequence
        ? TxMarketAggressor.buy : TxMarketAggressor.sell;
  }

  TxMarketMicrostructureSnapshot _aShareMicrostructure(
      TxSession session, String symbol) {
    final total = session.engine.fillCount;
    final start = total > 96 ? total - 96 : 0;
    final prints = <TxMarketPrint>[];
    for (var index = start; index < total; index++) {
      final fill = session.engine.fillAt(index);
      if (fill.symbol != symbol) continue;
      final buy = session.engine.order(fill.buyOrderId);
      final sell = session.engine.order(fill.sellOrderId);
      final aggressor = _aggressorForOrders(
          buySequence: buy.sequence, sellSequence: sell.sequence);
      final incoming = buy.sequence > sell.sequence ? buy : sell;
      prints.add(TxMarketPrint(
        id: fill.id,
        symbol: symbol,
        priceCents: fill.priceCents,
        quantity: fill.quantity,
        aggressor: aggressor,
        aggressorLabel: buy.sequence == sell.sequence
            ? null : _participantLabel(incoming.ownerId),
        timeLabel: fill.id,
      ));
    }
    return TxMarketMicrostructureSnapshot.fromPrints(
      prints: prints,
      bids: session.engine.depth(symbol, TxSide.buy, levels: 10),
      asks: session.engine.depth(symbol, TxSide.sell, levels: 10),
    );
  }

  TxMarketMicrostructureSnapshot _independentMicrostructure(
      TxIndependentMarketState state, String symbol) {
    final venue = state.runtime.venue;
    final total = venue.fillCount;
    final start = total > 96 ? total - 96 : 0;
    final prints = <TxMarketPrint>[];
    for (var index = start; index < total; index++) {
      final fill = venue.fillAt(index);
      if (fill.symbol != symbol) continue;
      final buy = venue.order(fill.buyOrderId);
      final sell = venue.order(fill.sellOrderId);
      final aggressor = _aggressorForOrders(
          buySequence: buy.sequence, sellSequence: sell.sequence);
      final incoming = buy.sequence > sell.sequence ? buy : sell;
      final minute = '${fill.gameDay}d '
          '${(fill.minuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
          '${(fill.minuteOfDay % 60).toString().padLeft(2, '0')}';
      prints.add(TxMarketPrint(
        id: fill.id,
        symbol: symbol,
        priceCents: fill.priceCents,
        quantity: fill.quantity,
        aggressor: aggressor,
        aggressorLabel: buy.sequence == sell.sequence
            ? null : incoming.ownerId,
        timeLabel: minute,
      ));
    }
    return TxMarketMicrostructureSnapshot.fromPrints(
      prints: prints,
      bids: venue.depth(symbol, TxSide.buy, levels: 10),
      asks: venue.depth(symbol, TxSide.sell, levels: 10),
    );
  }

  Widget _aShareFlowPanel(TxSession session, String symbol) {
    final snapshot = _aShareMicrostructure(session, symbol);
    return TxMarketFlowPanel(
      snapshot: snapshot,
      priceLabel: (cents) => '¥${money(cents)}',
      quantityUnit: '股',
      subtitle: '最近最多 24 笔已发生成交 · 主动方向由订单序列推导 · 盘口为十档快照',
    );
  }

  Widget _independentFlowPanel(TxIndependentMarketState state, String symbol) {
    final snapshot = _independentMicrostructure(state, symbol);
    return TxMarketFlowPanel(
      snapshot: snapshot,
      priceLabel: (cents) => _quotePrice(state.profile, cents),
      quantityUnit: state.profile.orderUnit,
      subtitle: '最近最多 24 笔已发生成交 · 主动方向由订单序列推导 · 盘口为十档快照',
    );
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackTicker = createTicker(_onPlaybackFrame);
    _startupStopwatch.start();
    _startupTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || (!_loading && !_historyWarming)) return;
      setState(() => _startupElapsed = _startupStopwatch.elapsed);
    });
    // Paint the first loading frame before opening a long historical store.
    // DB verification is required, but must not block the Flutter first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pause();
      // Android may emit inactive/hidden/paused as one transition. Reuse the
      // first safety flush instead of starting competing SQLite flushes.
      if (_backgroundFlush != null) return;
      final task = _flushPendingOnBackground();
      _backgroundFlush = task;
      unawaited(task.then<void>((_) {
        if (identical(_backgroundFlush, task)) _backgroundFlush = null;
      }, onError: (Object _, StackTrace __) {
        if (identical(_backgroundFlush, task)) _backgroundFlush = null;
      }));
    }
  }

  Future<void> _flushPendingOnBackground() async {
    final service = _trader;
    if (service == null) return;
    final operation = _operation;
    if (_busy && operation != null) {
      try {
        await operation;
      } catch (_) {
        return;
      }
    }
    if (!service.hasPendingPersistence) return;
    try {
      final saved = await service.flushPending();
      if (mounted) {
        setState(() => _notice =
            '后台切换前已安全保存 SQLite r${saved.revision}');
      }
    } catch (error) {
      if (mounted) {
        _pause();
        setState(() => _fault = '后台安全保存失败，已停止运行：$error');
      }
    }
  }

  // A pause is never gated by _busy. An in-flight atomic SQLite write is
  // allowed to settle, but no more game minutes are scheduled after the tap.
  void _pause() {
    if (mounted) _playbackTicker.stop();
    _previousFrame = null;
    _frameRenderGate.reset();
    _chartFrameRenderGate.reset();
    _flow.pause();
    _speedStopwatch.stop();
    if (_auto && mounted) setState(() => _auto = false);
  }

  // Vsync advances ONLY provisional time. The chart's cyan preview never
  // adds a fill, cash transaction or committed OHLCV observation.
  void _onPlaybackFrame(Duration elapsed) {
    if (!mounted || _fault != null) return;
    if (_flow.awaitingCommit) {
      // Keep only a small status-strip animation alive while the already
      // reached boundary is being audited and committed. Do not advance
      // [_seconds] or any market state until SQLite has acknowledged it.
      _previousFrame = elapsed;
      if (_settling.value) {
        _settlementPhase.value = TxSettlementMotion.phase(elapsed);
      }
      return;
    }
    if (!_auto) return;
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
    _clockSeconds = frameSeconds;
    // At high multipliers a single vsync can jump dozens of visual seconds.
    // The economic clock continues to advance, but only a durable pulse/minute
    // boundary is allowed to publish a display update. This keeps the status
    // strip, session cards and chart in one stable viewport instead of making
    // the entire page oscillate with the provisional price axis.
    final publishSeconds = _speed <= 60 && _frameRenderGate.shouldPaint(elapsed,
        force: frame.needsMinuteCommit || frame.needsPulseCommit);
    final publishChartSeconds = _chartFrameRenderGate.shouldPaint(elapsed,
        force: frame.needsMinuteCommit || frame.needsPulseCommit);
    if (publishSeconds && frameSeconds != _seconds.value) {
      _seconds.value = frameSeconds;
    }
    if (publishChartSeconds && frameSeconds != _chartSeconds.value) {
      _chartSeconds.value = frameSeconds;
    }
    if (frame.needsPulseCommit) {
      _pulse(frame.second);
    } else if (frame.needsMinuteCommit) {
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
    _chartFrameRenderGate.reset();
    _playbackTicker.start();
  }

  void _setStartupStage(String stage, double progress) {
    if (!mounted) return;
    setState(() {
      _startupStage = stage;
      _startupProgress = progress.clamp(0.0, 1.0).toDouble();
    });
  }

  void _finishStartupClock() {
    _startupStopwatch.stop();
    _startupTimer?.cancel();
    _startupTimer = null;
    if (mounted) {
      setState(() => _startupElapsed = _startupStopwatch.elapsed);
    }
  }

  String _startupTimeLabel() =>
      '${(_startupElapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';

  Future<void> _closeService(TxTradingService service) async {
    if (_serviceClosed) return;
    _serviceClosed = true;
    await service.close();
  }

  /// Adopt the audited SQLite head after a failed operation. A deferred,
  /// automatic candidate is preserved by the storage service when the on-disk
  /// head is unchanged; ambiguous player orders are never retried.
  Future<void> _recoverStorage() {
    final active = _recoveryOperation;
    if (active != null) return active;
    late Future<void> operation;
    operation = _recoverStorageNow().whenComplete(() {
      if (identical(_recoveryOperation, operation)) {
        _recoveryOperation = null;
      }
    });
    _recoveryOperation = operation;
    return operation;
  }

  Future<void> _recoverStorageNow() async {
    final service = _trader;
    if (service == null || _recoveringStorage) return;
    _pause();
    setState(() {
      _recoveringStorage = true;
      _historyWarming = true;
      _startupProgress = .72;
      _startupStage = '正在重新校验 SQLite 并恢复已落盘状态';
      _notice = '正在读取真实 SQLite 修订；优先保留可安全补写的自动行情';
    });
    try {
      final backgroundFlush = _backgroundFlush;
      if (backgroundFlush != null) {
        try {
          await backgroundFlush.timeout(const Duration(seconds: 15));
        } catch (error) {
          if (error is TimeoutException) {
            throw StateError('后台 SQLite 保存超过 15 秒仍未结束，请保持应用前台后重试');
          }
          // The background path already published the storage failure. The
          // recovery read below is still the authoritative next operation.
        }
      }
      final operation = _operation;
      if (_busy && operation != null) {
        try {
          await operation.timeout(const Duration(seconds: 15));
        } catch (error) {
          if (error is TimeoutException) {
            throw StateError('上一笔存储操作超过 15 秒仍未结束，请保持应用前台后重试');
          }
          // A failed operation is precisely the state this audit repairs.
        }
      }
      if (_busy) {
        throw StateError('上一笔存储操作仍在进行，暂不重复打开 SQLite');
      }
      await _independentMarkets?.waitForIdle();
      final loaded = await service.reopenAndVerify()
          .timeout(const Duration(seconds: 15));
      // A lifecycle flush can fail before the frame clock marks its own
      // pending boundary. Normalize that path into the same fail-closed flow
      // state before applying the audited SQLite position.
      if (!_flow.faulted) _flow.storageFailed();
      _flow.recoverAfterStorageAudit(
          pulseSecond: loaded.session.lastPulseSecond);
      _positionCache = null;
      _positionCacheRevision = null;
      _journalCache = null;
      _journalCacheRevision = null;
      _independentMarkets?.clearInMemoryStates();
      final baseline = TxLiveCandles.fromVerifiedHistory(
          <TxStoredSession>[loaded]);
      baseline.compactClosedFlatMinutes();
      if (!mounted) return;
      setState(() {
        _candles = baseline;
        _fault = null;
        _auto = false;
        // The verified account is usable now. The OHLC index is a display
        // read model and continues rebuilding in the background, so the
        // recovery button cannot leave the whole terminal looking stuck.
        _historyWarming = false;
        _clockSeconds = loaded.session.lastPulseSecond.toDouble();
        _seconds.value = _clockSeconds;
        _chartSeconds.value = _clockSeconds;
        _startupStage = '存档已恢复，K 线缓存后台重建中';
        _startupProgress = .82;
        _notice = service.lastRecoveryPreservedPending
            ? '已校验 SQLite；未落盘的自动行情已安全补写，游戏时间未回退'
            : '已恢复最后安全落盘状态；未确认的玩家操作不会自动重试';
      });
      if (_marketMode != TxMarketMode.aShare && mounted) {
        unawaited(_selectMarketMode(_marketMode, loaded.session));
      }
      _candleWarmup = _warmCandleHistory(service, loaded);
      // SQLite account recovery is authoritative. Rebuilding the display-only
      // candle index must not keep the recovery action in a loading state.
      unawaited(_candleWarmup!);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyWarming = false;
        _fault = 'SQLite 重新校验失败，仍保持停止状态：$error';
        _notice = '没有重试未确认的交易或行情';
      });
    } finally {
      if (mounted) setState(() => _recoveringStorage = false);
    }
  }

  /// The account head is authoritative and must be audited before the main
  /// screen becomes visible. The OHLC index is only a display read model, so
  /// its cache miss is warmed after the verified account is already visible.
  Future<void> _warmCandleHistory(
      TxTradingService service, TxStoredSession initial) async {
    try {
      _setStartupStage('正在校验已缓存 K 线', .76);
      var candles = await service.database.readCandleIndex(initial);
      if (candles == null) {
        _setStartupStage('缓存缺失，后台重建真实 OHLC 历史', .84);
        final recent = await service.database.readHistory(limit: 64);
        candles = TxLiveCandles.fromVerifiedHistory(recent);
        candles.compactClosedFlatMinutes();
        _setStartupStage('正在安全写入 K 线索引', .94);
        await service.database.seedCandleIndex(initial, candles);
      }
      candles!.compactClosedFlatMinutes();
      final readyCandles = candles!;
      if (!mounted) {
        await _closeService(service);
        return;
      }
      setState(() {
        _candles = readyCandles;
        _historyWarming = false;
        _startupProgress = 1.0;
        _startupStage = '启动完成';
        _notice = 'Rust 交易核心已启动，独立测试账户；行情默认暂停';
        _rustStatus = 'ARM64 ABI v2 已绑定';
      });
      _finishStartupClock();
      // Keep the requested multi-market first-look experience, but create
      // missing boards one at a time after the verified account and first
      // screen are ready. This prevents K-line history from extending the
      // critical cold-start path.
      unawaited(_prewarmIndependentMarkets());
    } catch (error) {
      // The index never authorizes a trade. Keep the verified account usable
      // with its real current mark, while making the non-authoritative cache
      // failure explicit instead of pretending that history was restored.
      if (!mounted) {
        await _closeService(service);
        return;
      }
      setState(() {
        _historyWarming = false;
        _startupProgress = .98;
        _startupStage = '账户已恢复，行情历史缓存未完成';
        _notice = '账户已安全恢复；K 线历史缓存失败，当前仅显示已校验基准：$error';
        _rustStatus = 'ARM64 ABI v2 已绑定 · K 线缓存异常';
      });
      _finishStartupClock();
    }
  }

  Future<void> _open() async {
    TxTradingService? service;
    try {
      _setStartupStage('正在打开 SQLite 数据文件', .08);
      final dir = await getApplicationSupportDirectory();
      final sqlite = File('${dir.path}/terminal_x_rust_v1.sqlite');
      _setStartupStage('正在完整校验 SQLite 存档', .18);
      service = TxTradingService(TxSqliteStore(
        NativeDatabase.createInBackground(sqlite)),
        initialSessionFactory: TxSession.freshWithAgents,
        persistentMarketWorker: true,
        nativeMarketWorker: Platform.isAndroid);
      final initial = await service.open();
      _setStartupStage('存档已校验，正在读取独立运行设置', .60);
      final policies = await Future.wait<int>(<Future<int>>[
        service.database.readCheckpointInterval(),
        service.database.readMarketPulseSeconds(),
      ]);
      final checkpointInterval = policies[0];
      final pulseSeconds = policies[1];
      final automaticSaveMinutes = service.automaticSaveMinutes;
      _flow.setPulseSeconds(pulseSeconds);
      // A single verified mark is enough to paint the chart shell. The full
      // bounded OHLC history is restored below, after the account is visible.
      final candles = TxLiveCandles.fromVerifiedHistory(
          <TxStoredSession>[initial]);
      if (!mounted) {
        await service.close();
        return;
      }
      _serviceClosed = false;
      setState(() {
        _trader = service;
        _independentMarkets = TxIndependentMarketService(service!.database);
        _candles = candles;
        _historyWarming = true;
        _checkpointInterval = checkpointInterval;
        _checkpointDraft = checkpointInterval;
        _automaticSaveMinutes = automaticSaveMinutes;
        _automaticSaveDraft = automaticSaveMinutes;
        _price.text = money(initial.session.lastPrice(_symbolName));
        _notice = '账户已安全恢复，正在后台恢复真实 K 线；交易入口暂不可用';
        _rustStatus = 'ARM64 ABI v2 已绑定 · K 线恢复中';
        _startupStage = '账户已恢复，正在后台恢复真实 K 线';
        _startupProgress = .70;
        _loading = false;
      });
      _clockSeconds = initial.session.lastPulseSecond.toDouble();
      _seconds.value = _clockSeconds;
      _chartSeconds.value = _clockSeconds;
      _candleWarmup = _warmCandleHistory(service, initial);
      unawaited(_candleWarmup!);
    } catch (e) {
      await service?.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _startupStage = '启动失败';
        _fault = 'SQLite 读取或校验失败，已停止交易并保留数据：$e';
      });
      _finishStartupClock();
    }
  }

  Future<void> _syncIndependentMarkets(TxSession session) async {
    final service = _independentMarkets;
    if (service == null) return;
    final states = await service.syncAll(
      gameDay: _clockGameDay(session),
      minuteOfDay: _clockMinuteOfDay(session),
      // Missing boards are prewarmed in a low-priority, one-board-at-a-time
      // path after the first frame. A-share minute commits only advance modes
      // the player has already opened, so cold-start cost is independent of
      // the number of market runtimes and their K-line history.
      openMissing: false,
    );
    final shouldPaint = _speed <= 60 || !_auto;
    final selected = states[_marketMode];
    if (mounted && selected != null && _marketMode != TxMarketMode.aShare) {
      _independentFault = null;
      // The trading/assets/records pages are not all under the market
      // ValueListenableBuilder; _perform's single completion build publishes
      // those pages together with the new CAS state.
      if (shouldPaint) {
        _marketRepaint.value++;
      }
    }
    // saveMarketRuntime audits the complete venue before its CAS commit. Do
    // not repeat that O(order/fill history) audit on the UI isolate after the
    // same successful save.
  }

  Future<void> _prewarmIndependentMarkets() async {
    if (_cancelIndependentPrewarm || _auto ||
        _marketMode != TxMarketMode.aShare) {
      return;
    }
    final service = _independentMarkets;
    if (service == null || _independentPrewarm != null) return;
    final task = _runIndependentPrewarm(service);
    _independentPrewarm = task;
    try {
      await task;
    } finally {
      if (identical(_independentPrewarm, task)) _independentPrewarm = null;
    }
  }

  Future<void> _runIndependentPrewarm(
      TxIndependentMarketService service) async {
    try {
      while (mounted && !_cancelIndependentPrewarm && !_auto &&
          _marketMode == TxMarketMode.aShare) {
        final session = _trader?.current.session;
        if (session == null) return;
        final mode = await service.prewarmNext(
          gameDay: _clockGameDay(session),
          minuteOfDay: _clockMinuteOfDay(session),
        );
        if (mode == null) return;
        // Give a market-selection tap a chance to enqueue between boards.
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      // Prewarming is optional display data. A selected board still opens
      // synchronously through the normal fail-closed market path.
      if (mounted && _marketMode == TxMarketMode.aShare) {
        setState(() => _notice = '独立市场后台预热暂停：$error');
      }
    }
  }

  Future<void> _selectMarketMode(TxMarketMode mode, TxSession session) async {
    if (mode == _marketMode &&
        (mode == TxMarketMode.aShare || _independentState != null)) return;
    // Board selection is a read-model change. It may queue its own CAS open
    // while an automatic A-share commit is settling, but it must not pause or
    // become a no-op merely because the playback worker is busy.
    if (!_ready) return;
    if (mode != TxMarketMode.aShare &&
        mode == _marketMode && _independentLoading) return;
    if (mode != TxMarketMode.aShare) _cancelIndependentPrewarm = true;
    if (mode == TxMarketMode.aShare) {
      setState(() {
        _marketMode = mode;
        _symbol = _symbol.clamp(0, TxSession.symbols.length - 1).toInt();
        _reduceOnly = false;
        _independentLoading = false;
        _independentFault = null;
        _price.text = money(_trader!.current.session.lastPrice(_symbolName));
      });
      return;
    }
    final service = _independentMarkets;
    if (service == null) return;
    setState(() {
      _marketMode = mode;
      _symbol = 0;
      _reduceOnly = false;
      _independentLoading = true;
      _independentFault = null;
    });
    try {
      final state = await service.open(
        mode: mode,
        gameDay: _clockGameDay(session),
        minuteOfDay: _clockMinuteOfDay(session),
      );
      if (!mounted || _marketMode != mode) return;
      setState(() {
        _independentLoading = false;
        _price.text = (state.profile.instruments.isEmpty)
            ? '' : (state.markPriceCents(
                    state.profile.instruments.first.symbol) / 100)
                .toStringAsFixed(2);
        _notice = '${state.profile.label} 独立撮合核心已连接 · SQLite CAS r${state.sequence}';
      });
      _marketRepaint.value++;
    } catch (error) {
      if (!mounted || _marketMode != mode) return;
      setState(() {
        _independentLoading = false;
        _independentFault = '独立${TxMarketProfile.of(mode).label}市场打开失败：$error';
        _notice = '未切换到不可验证的市场状态';
      });
    }
  }

  void _operate(Future<String> Function(TxTradingService) work,
      {bool automated = false, bool pulse = false}) {
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
      _settling.value = true;
      _pulseSettling.value = pulse;
      _settlementPhase.value = 0.0;
      _busy = true;
    }
    final operation = _perform(work, automated: automated, pulse: pulse);
    _operation = operation;
    unawaited(operation.then<void>((_) {
      if (identical(_operation, operation)) _operation = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_operation, operation)) _operation = null;
    }));
  }

  Future<void> _perform(Future<String> Function(TxTradingService) work,
      {required bool automated, required bool pulse}) async {
    try {
      final trader = _trader!;
      final before = trader.current;
      final notice = await work(trader);
      final after = trader.current;
      // Use the latest authoritative in-memory candidate for the live chart.
      // Automatic persistence may keep the same SQLite revision for several
      // game minutes, so revision changes alone are no longer a sufficient
      // repaint signal.
      final changed = before.revision != after.revision ||
          before.session.step != after.session.step ||
          before.session.marketTimeStep != after.session.marketTimeStep ||
          before.session.engine.fillCount != after.session.engine.fillCount;
      if (changed) {
        _candles!.addObservation(before.session, after.session);
        // Closed, no-print minutes are time gaps in the chart. This also
        // compacts v0.3.7 caches after the first verified refresh.
        _candles!.compactClosedFlatMinutes();
        // Keep the market page's session projection in step with the mutable
        // live candle cache. The per-frame preview still uses [_seconds], so
        // this notifier only fires after a real Rust candidate completes.
        // High-speed playback deliberately keeps the whole viewport stable.
        // The committed state is still updated; pausing or dropping the
        // multiplier repaints the latest candles/account in one frame.
        if (mounted && (!automated || _speed <= 60)) {
          _marketRepaint.value++;
        }
      }
      // A non-A-share board follows the same visible game clock, but owns its
      // venue/accounts/SQLite CAS envelope. It advances even while the A-share
      // automatic candidate is pending: the ledgers are separate, and a
      // closed independent session still produces no quote or print.
      // Rebase the independent clock before applying the committed A-share
      // step. At a minute boundary the frame clock is parked at 59.999s while
      // the worker runs; using that value with the newly incremented step
      // would advance the other board one extra minute.
      if (automated) {
        _clockSeconds = pulse ? _flow.minuteProgress * 60.0 : 0.0;
      }
      // Independent venues have minute resolution. A Rust intraminute pulse
      // must not cause a duplicate quote refresh or a full-screen repaint.
      if (_independentMarkets != null && changed &&
          (!automated || !pulse)) {
        await _syncIndependentMarkets(after.session);
      }
      if (automated) {
        // The isolated candidate finished computing. If the save cadence is
        // greater than one minute, SQLite remains explicitly marked pending;
        // the status strip exposes that durable boundary to the player.
        if (pulse) {
          _flow.completePulseCommit();
          _clockSeconds = _flow.minuteProgress * 60.0;
          if (mounted && _speed <= 60) _seconds.value = _clockSeconds;
          if (mounted) _chartSeconds.value = _clockSeconds;
        } else {
          _flow.completeMinuteCommit();
          _clockSeconds = 0;
          if (mounted) _seconds.value = 0;
          if (mounted) _chartSeconds.value = 0;
        }
        if (mounted) {
          _settling.value = false;
          _pulseSettling.value = false;
          _settlementPhase.value = 0.0;
        }
        if (_auto && !pulse && !after.pending) {
          _committedSpeed.record(
            elapsedMilliseconds: _speedStopwatch.elapsedMilliseconds,
            minute: after.session.step,
          );
        }
        // No arbitrary 60-minute playback cut-off. Checkpoint cadence bounds
        // recovery work; automatic save cadence bounds intentional loss after
        // a crash. Player actions and lifecycle transitions force a flush.
      }
      // Finally performs the single state build for this operation. The
      // status strip also exposes deferred SQLite work to the player.
      // Avoid a second full-page build while displaying the new revision.
      if (mounted) _notice = notice;
    } catch (e) {
      // Whether the DB commit was ambiguous or a chart invariant failed,
      // stop instead of risking another order against stale state.
      _pause();
      _flow.storageFailed();
      if (mounted) {
        _settling.value = false;
        _pulseSettling.value = false;
        _settlementPhase.value = 0.0;
      }
      if (mounted) setState(() =>
          _fault = '交易或历史检查异常；已暂停并保留数据：$e');
    } finally {
      if (mounted) {
        _busy = false;
        // At high multipliers a full-page rebuild per pulse/minute is the
        // source of visible viewport jitter. Keep the existing frame until
        // the user pauses, lowers the speed, or a foreground action needs it.
        if (!automated || _speed <= 60 || !_auto) {
          setState(() {});
        }
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

  void _pulse(int second) {
    _operate((service) async {
      final latency = Stopwatch()..start();
      final next = await service.marketPulse(second, deferSave: true);
      latency.stop();
      _pulseLatency.add(latency.elapsed);
      return 'Rust 真实盘口第 ${next.session.marketTimeStep} 分钟 ${second}s'
          '${next.pending ? ' · 待保存 ${next.pendingOperations} 项' :
          ' · SQLite r${next.revision}'}';
    }, automated: true, pulse: true);
  }

  void _tick({bool automatic = false}) {
    if (!automatic && _flow.running) _pause();
    if (!automatic && !_flow.awaitingCommit) {
      _flow.resetProvisional();
      _clockSeconds = 0;
      _seconds.value = 0;
      _chartSeconds.value = 0;
    }
    _operate((service) async {
    final latency = Stopwatch()..start();
    final next = await service.nextTick(deferSave: automatic);
    latency.stop();
    final timings = service.lastTickTimings;
    if (timings != null) {
      // Only a completed SQLite flush is a commit-latency sample.
      _commitLatency.add(latency.elapsed);
      _marketLatency.add(timings.market);
      _sqliteLatency.add(timings.sqlite);
    }
    return '模拟第 ${TxSimulationClock.gameDay(next.session.step)} 天 '
        '${TxSimulationClock.hhmm(next.session.step)} · '
        '${next.pending ? '待保存 ${service.pendingGameMinutes} 个游戏分钟' :
        'SQLite r${next.revision}'}';
    }, automated: automatic);
  }

  void _fastForwardClosed() {
    if (!_ready) return;
    _operate((service) async {
      final before = service.current.session.step;
      final next = await service.fastForwardClosed();
      final skipped = next.session.step - before;
      return skipped > 0
          ? '已快进 $skipped 个休市分钟；停在下一次开盘前，下一分钟恢复真实撮合'
          : '下一交易时段将在下一分钟开始，未跳过任何分钟';
    });
  }

  void _fastForwardIndependentClosed() {
    final service = _independentMarkets;
    final state = _independentState;
    if (!_ready || service == null || state == null || state.sessionStatus.isOpen) {
      return;
    }
    _independentOperate(() async {
      final before = _independentTimeStep(state);
      final next = await service.fastForwardClosed(mode: state.mode);
      final skipped = _independentTimeStep(next) - before;
      _marketRepaint.value++;
      return skipped > 0
          ? '${state.profile.label}已快进 $skipped 个休市分钟；停在下一次开盘前'
          : '${state.profile.label}下一交易时段将在下一分钟开始，未跳过任何分钟';
    });
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
    if (!_tradingReady) {
      setState(() => _notice = '当前交易核心尚未就绪，请等待市场校验完成后重试');
      return;
    }
    final sessionStatus = TxSession.marketSessionStatusAt(
        committedStep: _trader!.current.session.step,
        fractionalSeconds: _clockSeconds.floor());
    if (!sessionStatus.isOpen) {
      setState(() => _notice = 'A股${sessionStatus.label}，交易入口已锁定；开市后可继续下单');
      return;
    }
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
        quantity: n, limitPriceCents: limitPrice,
        timeInForce: _limit ? _timeInForce : TxTimeInForce.gtc);
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
      await service.flushPending();
      await service.database.setCheckpointInterval(selected);
      if (mounted) setState(() => _checkpointInterval = selected);
      return '完整检查点间隔已设为每 $selected 次成功保存；不改变自动保存周期';
    });
  }

  void _saveAutomaticSaveMinutes() {
    final selected = _automaticSaveDraft;
    _operate((service) async {
      await service.setAutomaticSaveMinutes(selected);
      if (mounted) setState(() => _automaticSaveMinutes = selected);
      return '自动 SQLite 保存周期已设为每 $selected 个游戏分钟；'
          '玩家操作、切后台和退出仍立即保存';
    });
  }

  Widget _title(String t, {String? sub}) => TxSectionHeader(
    title: t,
    subtitle: sub,
  );

  Widget _pageHeader({
    required IconData icon,
    required String eyebrow,
    required String title,
    required String subtitle,
    required String status,
    Color accent = TxTerminalColors.primary,
  }) => TxPageHeader(
    icon: icon,
    eyebrow: eyebrow,
    title: title,
    subtitle: subtitle,
    status: status,
    accent: accent,
  );

  Widget _metric(String label, String value) =>
      TxMetricTile(label: label, value: value);

  TxMarketSessionStatus _statusForMode(TxSession session, TxMarketMode mode) {
    final independent = _independentMarkets?.state(mode);
    if (mode != TxMarketMode.aShare && independent != null) {
      return independent.sessionStatus;
    }
    return TxMarketProfile.of(mode).schedule.status(
        gameDay: _clockGameDay(session),
        minuteOfDay: _clockMinuteOfDay(session));
  }

  /// This strip is intentionally available outside the market page. Switching
  /// boards changes the selected account view but does not pause playback.
  Widget _marketContextBar(TxSession session) => ValueListenableBuilder<double>(
    valueListenable: _seconds,
    builder: (context, _, child) => TxMarketContextStrip(
      selected: _marketMode,
      gameDay: _clockGameDay(session),
      minuteOfDay: _clockMinuteOfDay(session),
      enabled: _ready,
      onSelected: (mode) => unawaited(_selectMarketMode(mode, session)),
    ),
  );

  String _chartScope(TxMarketMode mode, String symbol) =>
      '${mode.name}:$symbol';

  _TxChartOverlayPrefs _chartPrefs(String scope) =>
      _chartOverlayPrefs.putIfAbsent(scope, _TxChartOverlayPrefs.new);

  List<TxChartOverlayLine> _aShareChartOverlays(
      TxSession session, String symbol) {
    final scope = _chartScope(TxMarketMode.aShare, symbol);
    final prefs = _chartPrefs(scope);
    final holdings = _positionsForRevision(
        session, _trader!.current.revision);
    final holding = holdings[symbol];
    if (holding == null || !holding.costKnown || holding.quantity <= 0) {
      return const <TxChartOverlayLine>[];
    }
    final average = holding.averagePriceCents.round();
    final pnl = holding.marketValueCents - holding.costBasisCents;
    final lines = <TxChartOverlayLine>[];
    if (prefs.showCost) {
      lines.add(TxChartOverlayLine(
        valueCents: average,
        label: '成本',
        valueLabel: '¥${money(average)} · ${signedMoney(pnl)}',
        color: TxTerminalColors.primary,
        dashed: false,
        scopeKey: scope,
      ));
    }
    if (prefs.showBreakeven) {
      lines.add(TxChartOverlayLine(
        valueCents: average,
        label: '保本',
        valueLabel: '¥${money(average)}',
        color: TxTerminalColors.gold,
        scopeKey: scope,
      ));
    }
    return lines;
  }

  int _independentBreakevenCents(TxIndependentMarketState state,
      TxMarketPosition position) {
    final feeBps = TxMarketFeePolicy.forMode(state.mode).takerBps;
    if (position.netQuantity > 0) {
      return (position.averageEntryCents * (10000 + feeBps) + 9999) ~/ 10000;
    }
    return math.max(1,
        (position.averageEntryCents * (10000 - feeBps)) ~/ 10000);
  }

  List<TxChartOverlayLine> _independentChartOverlays(
      TxIndependentMarketState state, String symbol) {
    final scope = _chartScope(state.mode, symbol);
    final prefs = _chartPrefs(scope);
    final position = state.playerRisk.positions[symbol];
    if (position == null || position.isFlat) {
      return const <TxChartOverlayLine>[];
    }
    final instrument = state.profile.instruments.firstWhere(
        (item) => item.symbol == symbol);
    final mark = state.markPriceCents(symbol);
    final pnl = (mark - position.averageEntryCents) * position.netQuantity *
        instrument.contractMultiplierUnits;
    final lines = <TxChartOverlayLine>[];
    if (prefs.showCost) {
      lines.add(TxChartOverlayLine(
        valueCents: position.averageEntryCents,
        label: '成本',
        valueLabel: '${_quotePrice(state.profile, position.averageEntryCents)} · '
            '${_quoteAmount(state.profile, pnl)}',
        color: TxTerminalColors.primary,
        dashed: false,
        scopeKey: scope,
      ));
    }
    if (prefs.showBreakeven) {
      final breakeven = _independentBreakevenCents(state, position);
      lines.add(TxChartOverlayLine(
        valueCents: breakeven,
        label: '保本',
        valueLabel: _quotePrice(state.profile, breakeven),
        color: TxTerminalColors.gold,
        scopeKey: scope,
      ));
    }
    if (prefs.showLiquidation) {
      final liquidation = state.player.estimatedLiquidationPriceCents(symbol);
      if (liquidation != null) {
        lines.add(TxChartOverlayLine(
          valueCents: liquidation,
          label: '强平',
          valueLabel: _quotePrice(state.profile, liquidation),
          color: TxTerminalColors.sell,
          scopeKey: scope,
        ));
      }
    }
    for (final condition in state.runtime.conditionalOrders.where(
        (order) => order.symbol == symbol)) {
      lines.add(TxChartOverlayLine(
        valueCents: condition.triggerPriceCents,
        label: condition.kind.label,
        valueLabel: '${condition.triggerOperator} '
            '${_quotePrice(state.profile, condition.triggerPriceCents)}',
        color: condition.kind == TxMarketConditionalOrderKind.stopLoss
            ? TxTerminalColors.sell : TxTerminalColors.buy,
        dashed: true,
        scopeKey: scope,
      ));
    }
    return lines;
  }

  Widget _chartOverlayControls({
    required bool marginMarket,
    required String scope,
  }) {
    final prefs = _chartPrefs(scope);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TxChartOverlayToggleBar(
          showCost: prefs.showCost,
          showBreakeven: prefs.showBreakeven,
          showLiquidation: prefs.showLiquidation,
          onCostChanged: (value) => setState(() => prefs.showCost = value),
          onBreakevenChanged: (value) =>
              setState(() => prefs.showBreakeven = value),
          onLiquidationChanged: (value) =>
              setState(() => prefs.showLiquidation = value),
        ),
        const SizedBox(height: 2),
        Text(
          marginMarket
              ? '成本线带当前浮动收益；保本线含平仓费率估算；强平线来自独立风险核心。'
              : '成本线带当前收益；A 股现金账户不使用保证金，因此没有强平线。',
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }

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
        _reduceOnly = false;
        _price.text = money(session.lastPrice(_symbolName));
      }),
    ),
  );

  // A speed change is applied only between completed durable minute writes.
  void _changeSpeed(int next) {
    if (!_ready || _flow.awaitingCommit || _flow.faulted) return;
    next = next.clamp(1, TxContinuousFlowClock.maxSupportedSpeed).toInt();
    if (_speed == next) return;
    final wasHighMultiplier = _speed > 60;
    _flow.setSpeed(next);
    _chartFrameRenderGate.reset();
    _committedSpeed.reset();
    _speedStopwatch..reset();
    if (_auto) {
      _speedStopwatch.start();
      _committedSpeed.record(elapsedMilliseconds: 0,
          minute: _trader!.current.session.step);
    }
    setState(() {
      _speed = next;
      if (!wasHighMultiplier && next > 60) {
        // Freeze the visible viewport at a durable minute boundary before
        // allowing the economic clock to run faster than the display.
        _seconds.value = 0;
      } else if (wasHighMultiplier && next <= 60) {
        // Reveal the authoritative provisional clock once the user opts back
        // into smooth intraminute display updates.
        _seconds.value = _clockSeconds;
      }
      _chartSeconds.value = _clockSeconds;
    });
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

  void _changeMarketPulseSeconds(int seconds) {
    if (!_ready || _flow.awaitingCommit || _flow.faulted ||
        seconds < 5 || seconds > 60 || seconds == _flow.pulseSeconds) return;
    _operate((service) async {
      await service.flushPending();
      await service.database.setMarketPulseSeconds(seconds);
      if (mounted) setState(() => _flow.setPulseSeconds(seconds));
      return '真实 Rust 盘口间隔已保存：每 $seconds 游戏秒；'
          '玩家操作仍经 SQLite 原子提交，自动行情按保存周期落盘';
    });
  }

  Future<void> _showCustomMarketPulse() async {
    if (!_ready || _flow.awaitingCommit || _flow.faulted) return;
    final controller = TextEditingController(text: '${_flow.pulseSeconds}');
    final choice = await showDialog<int>(context: context, builder: (context) =>
      AlertDialog(title: const Text('自定义真实盘口结算周期'), content: TextField(
        controller: controller, autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            labelText: '5～60 游戏秒', suffixText: '秒')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(
              int.tryParse(controller.text.trim())),
              child: const Text('应用')),
        ]));
    controller.dispose();
    if (!mounted || choice == null || choice < 5 || choice > 60 ||
        !_ready || _flow.awaitingCommit || _flow.faulted) return;
    _changeMarketPulseSeconds(choice);
  }

  Widget _depth(TxSession session) {
    final asks = session.engine.depth(_symbolName, TxSide.sell, levels: 10);
    final bids = session.engine.depth(_symbolName, TxSide.buy, levels: 10);
    return TxUnifiedOrderBook(
      title: '真实十档盘口 · A 股',
      subtitle: 'Rust 已提交委托 · 每 ${_flow.pulseSeconds} 游戏秒更新 · 点击价格填入限价',
      bids: bids,
      asks: asks,
      priceLabel: (cents) => '¥${money(cents)}',
      onPrice: (side, cents) => setState(() {
        _limit = true;
        _ticketSide = side == TxSide.buy ? TxSide.sell : TxSide.buy;
        _price.text = money(cents);
        _page = 1;
      }),
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
    _reduceOnly = false;
    _page = 1;
  });

  Widget _market(TxSession session) => ValueListenableBuilder<int>(
    valueListenable: _marketRepaint,
    builder: (context, _, child) => _marketContent(
        _trader?.current.session ?? session),
  );

  Widget _marketContent(TxSession session) {
    final profile = TxMarketProfile.of(_marketMode);
    Widget modeSelector() => _marketContextBar(session);
    Widget sessionCard() => ValueListenableBuilder<double>(
      valueListenable: _seconds,
      builder: (context, seconds, child) {
        final status = TxSession.marketSessionStatusAt(
          committedStep: session.step,
          fractionalSeconds: seconds.floor().clamp(0, 59).toInt(),
        );
        final gameDay = TxRealtimeClock.gameDay(
            session.step, seconds.floor());
        final minuteOfDay = TxRealtimeClock.gameMinuteOfDay(
            session.step, seconds.floor());
        final openAlternatives = TxMarketProfile.values.where((item) {
          if (item.mode == TxMarketMode.aShare) return false;
          return item.schedule.status(
              gameDay: gameDay, minuteOfDay: minuteOfDay).isOpen;
        }).toList();
        final minutes = status.minutesToTransition;
        return Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  status.isOpen
                      ? Icons.wb_sunny_outlined
                      : Icons.nightlight_outlined,
                  size: 18,
                  color: status.isOpen
                      ? TxTerminalColors.buy
                      : TxTerminalColors.primary,
                ),
                const SizedBox(width: 7),
                Expanded(child: Text('市场时段 · ${status.label}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                if (minutes != null)
                  Text('约 $minutes 分钟',
                      style: const TextStyle(
                          fontSize: 10,
                          color: TxTerminalColors.secondaryText)),
              ]),
              const SizedBox(height: 5),
              Text(
                status.isOpen
                    ? '开市中：成交与 K 线只来自真实撮合'
                    : '休市中：无成交、无临时 K 线波动；可切换到当前开市的其他板块',
                style: const TextStyle(
                    fontSize: 10, color: TxTerminalColors.secondaryText),
              ),
              if (!status.isOpen) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _ready ? _fastForwardClosed : null,
                    icon: const Icon(Icons.fast_forward, size: 17),
                    label: const Text('快进到下次开盘前'),
                  ),
                ),
                if (openAlternatives.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text('当前开市的其他板块', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: TxTerminalColors.cyan)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final alternative in openAlternatives)
                      OutlinedButton.icon(
                        onPressed: _ready
                            ? () => unawaited(_selectMarketMode(
                                alternative.mode, session))
                            : null,
                        icon: const Icon(Icons.swap_horiz, size: 15),
                        label: Text('${alternative.label} · '
                            '${alternative.instruments.first.symbol}'),
                      ),
                  ]),
                ],
              ],
            ],
          ),
        ));
      },
    );
    if (_independentMode) {
      return _independentMarketContent(session, profile, modeSelector());
    }
    final minuteFills = session.currentMinuteFills
        .where((f) => f.symbol == _symbolName).toList();
    final minuteVolume = minuteFills.fold<int>(0, (sum, f) => sum + f.quantity);
    final durablePrice = _trader!.durableCurrent.session.lastPrice(_symbolName);
    final candles = _candles!.forSymbol(_symbolName);
    final chartScope = _chartScope(TxMarketMode.aShare, _symbolName);
    final chartOverlays = _aShareChartOverlays(session, _symbolName);
    Widget chartCard() => RepaintBoundary(child: Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _chartOverlayControls(marginMarket: false, scope: chartScope),
        const SizedBox(height: 4),
        ValueListenableBuilder<double>(
          valueListenable: _chartSeconds,
          builder: (context, seconds, child) {
            final showPreview = _marketPreviewAllowed(session, seconds);
            return TxCandleChart(
              key: ValueKey('${_marketMode.name}:$_symbolName'),
              candles: candles,
              overlays: chartOverlays,
              marketScope: chartScope,
              pending: _trader!.current.pending,
              activeMinuteStep: showPreview
                  ? session.step + 1
                  : (session.lastPulseSecond > 0
                      ? session.marketTimeStep : null),
              indicativeFramePriceCents: showPreview
                  ? _indication(session, seconds) : null,
              previewSeconds: showPreview ? seconds : null,
            );
          },
        ),
      ]),
    )));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _pageHeader(
        icon: Icons.candlestick_chart_rounded,
        eyebrow: 'MARKET DESK',
        title: '${profile.label}行情',
        subtitle: '价格、成交、盘口与市场结构；只把真实撮合结果写入 K 线与资产。',
        status: '主市场 · Rust 真实撮合',
        accent: TxTerminalColors.cyan,
      ),
      modeSelector(),
      // Put the chart before the verbose session/radar cards so the first
      // market frame is immediately useful on a phone-sized viewport.
      chartCard(),
      _marketDeskOverview(session),
      _aShareFlowPanel(session, _symbolName),
      sessionCard(),
      TxMarketRadar(quotes: [
        for (var i=0;i<TxSession.symbols.length;i++)
          TxRadarQuote(symbol:TxSession.symbols[i],
            priceCents:session.lastPrice(TxSession.symbols[i]),
            regime:_regimeName(session.step,i)),
        ],selectedIndex:_symbol,onSelect:(i)=>setState(() {
          _symbol=i;
          _price.text=money(session.lastPrice(_symbolName));
        })),
      TxMarketHero(symbol: _symbolName, committedPriceCents: durablePrice,
        step: session.step, seconds: _chartSeconds,
        quoteCurrency: profile.quoteCurrency,
        coreConnected: _tradingReady,
        indicativeCents: (seconds) => _displayIndication(session, seconds),
        pending: _trader!.current.pending,
        onBuy: profile.isCoreConnected
            ? () => _openTradeTicket(TxSide.buy) : null,
        onSell: profile.isCoreConnected
            ? () => _openTradeTicket(TxSide.sell) : null),
      TxMarketEcosystemCard(session: session, symbol: _symbolName,
        profile: profile),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('模拟市场参与者', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('2 个有限库存做市商 + 4 个独立资金账户的模拟交易者；'
              '它们会主动交易和提供流动性，玩家不操作也可能有成交。',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text('当前市场环境：${_regimeName(session.step, _symbol)}'),
          if (Platform.isAndroid) Text('交易：Rust 原生撮合 · Dart 界面镜像 · $_rustStatus',
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
          Text('本游戏分钟：${minuteFills.length} 笔真实撮合 · '
              '$minuteVolume 股成交量'),
          const Text('所有成交均在真实订单簿按价格与时间撮合；'
              '不模拟外部证券、不保证每一分钟都有成交。',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ))),
      _depth(session),
      _phaseTimeline(session.step),
      /*
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
            const Text('真实盘口结算', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            for (final seconds in [5, 10, 15, 30, 60])
              Padding(padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(label: Text('${seconds}s',
                    style: const TextStyle(fontSize: 10)),
                  selected: _flow.pulseSeconds == seconds,
                  onSelected: _ready && !_flow.awaitingCommit
                      ? (_) => _changeMarketPulseSeconds(seconds)
                      : null)),
            TextButton(onPressed: _ready && !_flow.awaitingCommit
                ? _showCustomMarketPulse : null,
              child: const Text('自定义', style: TextStyle(fontSize: 10))),
          ])),
          const Text('间隔越短盘口越实时，但 Rust 盘口计算次数越多；SQLite 自动保存由上方周期单独控制。'
              '60s 为原有分钟结算模式。',
              style: TextStyle(color: Colors.white54, fontSize: 10)),
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
          Text('目标 ${_speed}× · 实际已落盘 ${_committedSpeed.achievedMultiplier.toStringAsFixed(1)}×'
              ' · 以完整 SQLite 保存为准',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          if (_pulseLatency.count > 0)
            Text('实时盘口最近 ${_pulseLatency.count} 次候选 p95 '
                '${_pulseLatency.p95Milliseconds} ms（Rust worker，不含 SQLite 落盘）',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          if (_commitLatency.count > 0) ...[
            Text('最近 ${_commitLatency.count} 次有效分钟提交耗时 p95 '
                '${_commitLatency.p95Milliseconds} ms（含撮合及 SQLite）',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
            if (_marketLatency.count > 0 && _sqliteLatency.count > 0)
              Text('阶段 p95：Rust/市场 ${_marketLatency.p95Milliseconds} ms'
                  ' · SQLite/校验 ${_sqliteLatency.p95Milliseconds} ms'
                  '（分别统计，不直接相加）',
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
      const Text('分时右端青色连续线及各周期青色空心蜡烛为未结算指示报价；真实 OHLC、均线与成交量均取自真实撮合。'
          '自动保存周期内的实时图可包含已标注的待保存候选，重启只恢复 SQLite 已落盘记录；成交量不把秒级报价变动伪造成交易。',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
      */
    ]);
  }

  Widget _independentMarketContent(TxSession session,
      TxMarketProfile profile, Widget selector) {
    final state = _independentState;
    if (_independentLoading || state == null) {
      return ListView(padding: const EdgeInsets.all(14), children: [
        selector,
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(child: Text('正在打开${profile.label}独立账户、订单簿与 SQLite 快照')),
          ]),
        )),
        if (_independentFault != null)
          SelectableText(_independentFault!,
              style: const TextStyle(color: red)),
      ]);
    }
    final index = _symbol.clamp(0, profile.instruments.length - 1).toInt();
    final instrument = profile.instruments[index];
    final symbol = instrument.symbol;
    final status = state.sessionStatus;
    final mark = state.markPriceCents(symbol);
    final candles = state.candlesFor(symbol);
    final chartScope = _chartScope(state.mode, symbol);
    final chartOverlays = _independentChartOverlays(state, symbol);
    final canTrade = _tradingReady && status.isOpen;
    Widget chartCard() => Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('真实成交 K 线',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${candles.length} 根 · ${state.runtime.venue.fillCount} 笔市场成交',
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
        ]),
        const SizedBox(height: 4),
        _chartOverlayControls(
            marginMarket: instrument.usesMargin, scope: chartScope),
        const SizedBox(height: 3),
        const Text('只由已发生的真实成交构造 OHLCV；盘口报价不会伪造 K 线。',
            style: TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
        const SizedBox(height: 7),
        ValueListenableBuilder<double>(
          valueListenable: _chartSeconds,
          builder: (context, seconds, child) {
            final marketOpen = state.profile.schedule.status(
                gameDay: _clockGameDay(session),
                minuteOfDay: _clockMinuteOfDay(session)).isOpen;
            final preview = marketOpen
                ? _independentIndicativePrice(state, session, symbol, seconds)
                : null;
            final previewAllowed = preview != null &&
                _independentPreviewAllowed(state, session, seconds);
            return TxCandleChart(
              key: ValueKey('${state.mode.name}:$symbol'),
              candles: candles,
              overlays: chartOverlays,
              marketScope: chartScope,
              activeMinuteStep: _independentTimeStep(state),
              indicativePriceCents: preview?.round(),
              indicativeFramePriceCents: preview,
              previewSeconds: previewAllowed ? seconds : null,
            );
          },
        ),
      ]),
    ));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _pageHeader(
        icon: Icons.public_rounded,
        eyebrow: 'ALTERNATIVE VENUE',
        title: '${profile.label}行情',
        subtitle: '独立现金、持仓、订单簿和历史；休市时冻结本板块并提示可用的其他开市市场。',
        status: '独立账户 · CAS 快照',
        accent: TxTerminalColors.gold,
      ),
      selector,
      // The primary quote view comes before the explanatory account cards.
      chartCard(),
      _marketDeskOverview(session),
      _independentFlowPanel(state, symbol),
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(status.isOpen ? Icons.radio_button_checked : Icons.pause_circle,
              size: 18,
              color: status.isOpen ? TxTerminalColors.buy :
                  Colors.amberAccent),
          const SizedBox(width: 7),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${profile.label} · ${status.label}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(status.isOpen
                ? '独立账户和订单簿已连接；成交、OHLCV、资金和持仓只接受真实撮合'
                : '当前板块休市；没有成交或临时 K 线波动，可切换到其他开市板块',
                style: const TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
            if (!status.isOpen) ...[
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _ready && !_busy
                      ? _fastForwardIndependentClosed : null,
                  icon: const Icon(Icons.fast_forward, size: 16),
                  label: const Text('快进到下次开盘前'),
                ),
              ),
            ],
          ])),
          Text('CAS r${state.sequence}', style: const TextStyle(
              fontSize: 10, color: TxTerminalColors.secondaryText)),
        ]),
      )),
      TxMarketRadar(
        quotes: [
          for (final item in profile.instruments)
            TxRadarQuote(
              symbol: item.symbol,
              priceCents: state.markPriceCents(item.symbol),
              regime: '独立订单簿 · ${status.label}',
            ),
        ],
        selectedIndex: index,
        quoteCurrency: profile.quoteCurrency,
        onSelect: (value) => setState(() {
          _symbol = value;
          _price.text = (state.markPriceCents(
                  profile.instruments[value].symbol) / 100).toStringAsFixed(2);
        }),
      ),
      TxMarketHero(
        symbol: symbol,
        committedPriceCents: mark,
        step: _independentSessionStep(state),
        seconds: _chartSeconds,
        quoteCurrency: profile.quoteCurrency,
        coreConnected: true,
        connectionLabel: 'DART · 独立已连接',
        // The large cyan number follows the same explicitly-labelled
        // intraminute reference as the chart; only [committedPriceCents] is a
        // durable mark and can be used by the execution core.
        committedOnly: false,
        indicativeCents: (seconds) => _independentIndicativePrice(
            state, session, symbol, seconds),
        pending: false,
        onBuy: canTrade ? () => _openTradeTicket(TxSide.buy) : null,
        onSell: canTrade ? () => _openTradeTicket(TxSide.sell) : null,
      ),
      _independentDepth(state, symbol),
      _independentParticipantPulse(state, symbol),
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('独立市场账户', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('权益 ${_quoteAmount(profile, state.playerRisk.equityCents)} · '
              '现金 ${_quoteAmount(profile, state.playerRisk.cashCents)} · '
              '可用保证金 ${_quoteAmount(profile, state.playerRisk.freeMarginCents)}'),
          Text('持仓 ${state.playerRisk.positions.values
              .where((position) => !position.isFlat).length} 个 · '
              '已实现 ${_quoteAmount(profile, state.playerRisk.realizedPnlCents)}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 4),
          const Text('这是与 A 股现货完全隔离的单机市场账户；切换板块不会改写另一市场的现金或持仓。',
              style: TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
      )),
      _independentRiskTerms(state, symbol),
    ]);
  }

  Widget _independentDepth(TxIndependentMarketState state, String symbol,
      {bool allowTicket = false}) {
    final bids = state.runtime.venue.depth(symbol, TxSide.buy, levels: 10);
    final asks = state.runtime.venue.depth(symbol, TxSide.sell, levels: 10);
    return TxUnifiedOrderBook(
      title: '真实十档盘口 · ${state.profile.label}',
      subtitle: '独立订单簿快照 · 点击价格填入限价，不绕过确认与风控',
      bids: bids,
      asks: asks,
      priceLabel: (cents) => _quotePrice(state.profile, cents),
      onPrice: allowTicket && _ready ? (side, cents) => setState(() {
        _limit = true;
        _ticketSide = side == TxSide.buy ? TxSide.sell : TxSide.buy;
        _timeInForce = TxTimeInForce.gtc;
        _price.text = (cents / 100).toStringAsFixed(2);
      }) : null,
    );
  }

  Widget _independentParticipantPulse(
      TxIndependentMarketState state, String symbol) {
    const strategies = <String, String>{
      'SMART-TREND': '趋势',
      'SMART-MEAN': '均值',
      'SMART-MOMENTUM': '动量',
      'SMART-SCALPER': '短线',
    };
    final available = strategies.keys.where(
        state.runtime.venue.accounts.containsKey).toList();
    final prints = state.runtime.venue.fillsForMinute(
        state.runtime.gameDay, state.runtime.minuteOfDay, symbol: symbol)
        .where((fill) {
      final buy = state.runtime.venue.order(fill.buyOrderId).ownerId;
      final sell = state.runtime.venue.order(fill.sellOrderId).ownerId;
      return strategies.containsKey(buy) || strategies.containsKey(sell);
    }).length;
    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_graph_rounded, size: 18,
              color: TxTerminalColors.cyan),
          const SizedBox(width: 7),
          const Expanded(child: Text('智能交易者引擎',
              style: TextStyle(fontWeight: FontWeight.w800))),
          Text('本分钟 $prints 笔真实成交',
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
        ]),
        const SizedBox(height: 5),
        Text(available.isEmpty
            ? '旧快照尚未迁移策略账户；后续开盘会继续使用现有有限库存流量。'
            : '四类有限资金策略只通过真实盘口下单：被拒、缺深度或保证金不足时不会伪造成交。',
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 7),
          Wrap(spacing: 5, runSpacing: 4, children: [
            for (final id in available)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: TxTerminalColors.cyan.withAlpha(18),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: TxTerminalColors.cyan.withAlpha(70)),
                ),
                child: Text(strategies[id]!, style: const TextStyle(
                    fontSize: 10, color: TxTerminalColors.cyan)),
              ),
          ]),
        ],
      ]),
    ));
  }

  Widget _phaseTimeline(int committedMinute) {
    final events = TxMarketPhaseTimeline.recent(currentStep: committedMinute);
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('市场阶段与流动性环境',
          style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        const Text('由本地撮合规则决定的市场状态，不是外部新闻或真实成交。',
          style: TextStyle(fontSize: 11, color: Colors.white60)),
        if (events.isEmpty) const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('当前时段尚无已发生的状态切换记录',
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
    if (_independentMode) {
      final state = _independentState;
      if (state != null) _showIndependentMarketEstimate(state, side);
      return;
    }
    if (!_tradingReady || _limit) return;
    final quantity = int.tryParse(_qty.text.trim());
    if (quantity == null || quantity < 1 || quantity > TxEngine.maxQuantity) {
      setState(() => _notice = '请先输入有效的市价委托股数');
      return;
    }
    // This is a synchronous read-only preflight against the latest real
    // in-memory book. Trigger only on request, never on a frame or each
    // keystroke; a pending candidate remains explicitly labelled below.
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
          Text(saved.pending
              ? '当前内存盘口候选 · SQLite 恢复边界 r${saved.revision}'
              : '已提交存档 r${saved.revision} 的盘口快照',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text('申请 $quantity 股 · 预计可成交 ${estimate.executableShares} 股'),
          Text('预计未成交 ${estimate.unfilledShares} 股'),
          Text('预计成交金额 ¥${money(estimate.notionalCents)}'),
          Text('预计成交均价 ${average == null ? '—' : '¥${(average / 100).toStringAsFixed(4)}'}'),
          Text('最优价 ${price(estimate.bestPriceCents)}'
              ' · 最差价 ${price(estimate.worstPriceCents)}'),
          Text('预计消耗 ${estimate.levelsConsumed} 档可见流动性'),
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
    if (_independentMode) {
      final state = _independentState;
      if (state != null) _applyIndependentTicketPercent(state, percent);
      return;
    }
    if (!_tradingReady) return;
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

  void _applyIndependentTicketPercent(
      TxIndependentMarketState state, int percent) {
    final profile = state.profile;
    final symbol = profile.instruments[_symbol
        .clamp(0, profile.instruments.length - 1).toInt()].symbol;
    final risk = state.playerRisk;
    final position = risk.positions[symbol];
    int maximum;
    if (_ticketSide == TxSide.sell && position != null &&
        position.availableToClose > 0) {
      maximum = position.availableToClose;
    } else if (_ticketSide == TxSide.sell && !profile.supportsShort) {
      maximum = 0;
    } else {
      final asks = state.runtime.venue.depth(symbol, TxSide.sell);
      final reference = _limit ? _cents(_price.text) :
          (asks.isEmpty ? null : asks.first.priceCents);
      maximum = reference == null ? 0 :
          (risk.freeMarginCents ~/ math.max(1,
              state.player.requiredEntryCents(
                  symbol: symbol, priceCents: reference, quantity: 1)));
    }
    maximum = maximum.clamp(0, TxEngine.maxQuantity).toInt();
    if (maximum == 0) {
      setState(() => _notice = '当前独立账户缺少可用保证金、对手盘或可平仓数量');
      return;
    }
    final amount = (maximum * percent ~/ 100).clamp(1, maximum).toInt();
    _qty.text = '$amount';
  }

  void _showIndependentMarketEstimate(
      TxIndependentMarketState state, TxSide side) {
    if (_limit) return;
    final quantity = int.tryParse(_qty.text.trim());
    if (quantity == null || quantity < 1 || quantity > TxEngine.maxQuantity) {
      setState(() => _notice = '请先输入有效的独立市场委托数量');
      return;
    }
    final profile = state.profile;
    final symbol = profile.instruments[_symbol
        .clamp(0, profile.instruments.length - 1).toInt()].symbol;
    final preview = _independentMarkets!.preview(
      mode: state.mode,
      symbol: symbol,
      side: side,
      kind: TxKind.market,
      quantity: quantity,
      limitPriceCents: null,
      timeInForce: TxTimeInForce.gtc,
      gameDay: state.runtime.gameDay,
      minuteOfDay: state.runtime.minuteOfDay,
    );
    final average = preview.vwapCents == null ? '—' :
        _quotePrice(profile, preview.vwapCents!.round());
    final best = preview.bestPriceCents == null ? '—' :
        _quotePrice(profile, preview.bestPriceCents!);
    final worst = preview.worstPriceCents == null ? '—' :
        _quotePrice(profile, preview.worstPriceCents!);
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('${side == TxSide.buy ? '买入' : '卖出'}市价试算 · $symbol'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('独立订单簿 CAS r${state.sequence}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text('申请 $quantity · 预计成交 ${preview.executableQuantity}'),
          Text('预计剩余 ${preview.remainingQuantity} · 消耗 ${preview.levelsConsumed} 档'),
          Text('预计 VWAP $average · 最优 $best · 最差 $worst'),
          if (!preview.accepted || !preview.fullyExecutable)
            Text('执行提示：${preview.reason ?? '可见深度不足，可能部分成交'}',
                style: const TextStyle(color: Colors.amberAccent)),
          const SizedBox(height: 8),
          const Text('只读试算，不冻结资金、不修改订单簿；确认时会重新执行风险和深度校验。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      )),
      actions: [TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('关闭试算'),
      )],
    ));
  }

  // The compact, tap-to-fill order book is read from verified resting bids
  // and asks. No synthetic quote enters an actual limit ticket. The small
  // BBO/spread/imbalance strip makes the market microstructure visible before
  // a player chooses a price, while keeping the actual matching engine as the
  // only source of fills.
  Widget _tradeQuickDepth(List<TxBookLevel> bids,
      List<TxBookLevel> asks) {
    final insight = TxOrderBookInsight.fromLevels(bids: bids, asks: asks);
    final maxQty = [...bids.map((level) => level.quantity),
        ...asks.map((level) => level.quantity), 1]
      .reduce((a, b) => a > b ? a : b);
    final bidFraction = insight.bidShareFraction;
    String best(int? cents) => cents == null ? '—' : '¥${money(cents)}';
    final spread = insight.spreadCents == null
        ? '—'
        : '¥${money(insight.spreadCents!)}';
    Widget column(String title, List<TxBookLevel> levels, Color tint) =>
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: tint,
              fontSize: 12, fontWeight: FontWeight.bold)),
          if (levels.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('暂无挂单', style: TextStyle(fontSize: 11))),
          for (final level in levels.take(5)) InkWell(
            onTap: !_tradingReady ? null : () => setState(() {
              _limit = true;
              _ticketSide = tint == green ? TxSide.sell : TxSide.buy;
              _timeInForce = TxTimeInForce.gtc;
              _price.text = money(level.priceCents);
            }),
            child: SizedBox(height: 28, child: Stack(children: [
              Align(alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: level.quantity / maxQty,
                  child: Container(height: 22, color: tint.withAlpha(30)))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text('¥${money(level.priceCents)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tint, fontSize: 11))),
                  Text('${level.quantity}',
                      style: const TextStyle(fontSize: 11,
                          color: Colors.white70)),
                ])),
            ])),
          ),
        ]));
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('快捷盘口 · 点击价格填入限价',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        Wrap(spacing: 12, runSpacing: 4, children: [
          Text('买一 ${best(insight.bestBidCents)}',
              style: const TextStyle(color: green, fontSize: 11)),
          Text('卖一 ${best(insight.bestAskCents)}',
              style: const TextStyle(color: red, fontSize: 11)),
          Text('价差 $spread',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
        if (bidFraction != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: bidFraction, minHeight: 4,
              backgroundColor: red,
              valueColor: const AlwaysStoppedAnimation<Color>(green)),
          Text('可见五档买盘占比 ${(bidFraction * 100).toStringAsFixed(1)}%'
              ' · 只表示当前挂单量，不是涨跌预测',
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
        const SizedBox(height: 5),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          column('买盘 Bids · 点击卖出', bids, green),
          const SizedBox(width: 14),
          column('卖盘 Asks · 点击买入', asks, red),
        ]),
        const Text('可见委托簿快照，非实时互联网行情。',
            style: TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
    ));
  }

  void _confirmIndependentTicket() {
    final state = _independentState;
    if (state == null || !_tradingReady) return;
    final status = state.sessionStatus;
    if (!status.isOpen) {
      setState(() => _notice = '${state.profile.label}${status.label}，交易入口已锁定');
      return;
    }
    final profile = state.profile;
    final symbol = profile.instruments[_symbol
        .clamp(0, profile.instruments.length - 1).toInt()].symbol;
    final quantityText = _qty.text.trim();
    final quantity = int.tryParse(quantityText);
    final limit = _limit ? _cents(_price.text.trim()) : null;
    if (quantity == null || quantity < 1 || quantity > TxEngine.maxQuantity ||
        (_limit && limit == null)) {
      setState(() => _notice = '请检查独立市场委托数量和限价');
      return;
    }
    if (_auto) _pause();
    FocusManager.instance.primaryFocus?.unfocus();
    final side = _ticketSide;
    final reduceOnly = _reduceOnly;
    final sequence = state.sequence;
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('确认${side == TxSide.buy ? '买入' : '卖出'} · $symbol'),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('市场：${profile.label} · 独立账户'),
        Text('类型：${_limit ? '限价 ${_quotePrice(profile, limit!)}' : '市价'}'),
        Text('数量：$quantity · TIF：${_limit ? _timeInForce.label : 'GTC'}'),
        Text('仓位意图：${reduceOnly ? '只减仓，不反向开仓' : '普通开仓/加减仓'}'),
        Text('订单簿修订：CAS r$sequence'),
        const SizedBox(height: 8),
        const Text('确认后会以当前本地订单簿重新撮合；余额、保证金、手续费和成交记录原子写入独立市场快照。',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: () {
          Navigator.of(dialogContext).pop();
          if (!mounted) return;
          final current = _independentState;
          if (current == null || current.sequence != sequence ||
              _marketMode != current.mode || _ticketSide != side ||
              _reduceOnly != reduceOnly ||
              _qty.text.trim() != quantityText ||
              (_limit ? _cents(_price.text.trim()) : null) != limit) {
            setState(() => _notice = '独立市场快照或委托参数已变化，请重新检查');
            return;
          }
          _independentTrade(side, reduceOnly: reduceOnly);
        }, child: Text('确认${side == TxSide.buy ? '买入' : '卖出'}')),
      ],
    ));
  }

  void _independentTrade(TxSide side, {required bool reduceOnly}) {
    final service = _independentMarkets;
    final state = _independentState;
    if (service == null || state == null || !_tradingReady) return;
    final quantity = int.tryParse(_qty.text.trim());
    final limit = _limit ? _cents(_price.text.trim()) : null;
    if (quantity == null || quantity < 1 || quantity > TxEngine.maxQuantity ||
        (_limit && limit == null)) return;
    _independentOperate(() async {
      final order = await service.place(
        mode: state.mode,
        symbol: state.profile.instruments[_symbol
            .clamp(0, state.profile.instruments.length - 1).toInt()].symbol,
        side: side,
        kind: _limit ? TxKind.limit : TxKind.market,
        quantity: quantity,
        limitPriceCents: limit,
        timeInForce: _limit ? _timeInForce : TxTimeInForce.gtc,
        gameDay: state.runtime.gameDay,
        minuteOfDay: state.runtime.minuteOfDay,
        reduceOnly: reduceOnly,
      );
      _marketRepaint.value++;
      return '${order.id} · ${reduceOnly ? '只减仓 ' : ''}成交${order.filled} · 余量${order.remaining} · '
          '${order.status.name} · CAS r${state.sequence}';
    });
  }

  void _cancelIndependent(String orderId) {
    final service = _independentMarkets;
    final state = _independentState;
    if (service == null || state == null) return;
    _independentOperate(() async {
      final order = await service.cancel(mode: state.mode, orderId: orderId);
      _marketRepaint.value++;
      return '$orderId 已撤销 · ${order.status.name} · CAS r${state.sequence}';
    });
  }

  void _cancelIndependentConditional(String orderId) {
    final service = _independentMarkets;
    final state = _independentState;
    if (service == null || state == null) return;
    _independentOperate(() async {
      final order = await service.cancelConditional(
          mode: state.mode, orderId: orderId);
      _marketRepaint.value++;
      return '${order.kind.label}保护单已取消 · ${order.symbol} · CAS r${state.sequence}';
    });
  }

  void _changeIndependentLeverage(TxMarketMode mode, int multiple) {
    final service = _independentMarkets;
    final state = _independentState;
    if (service == null || state == null || state.mode != mode ||
        state.player.leverageMultiple == multiple) return;
    _independentOperate(() async {
      final selected = await service.setPlayerLeverage(
          mode: mode, multiple: multiple);
      _marketRepaint.value++;
      return '${state.profile.label}账户杠杆已设为 ${selected}× · '
          '已有持仓时不会自动改写保证金规则';
    });
  }

  void _changeIndependentMarginMode(
      TxMarketMode mode, TxMarginMode marginMode) {
    final service = _independentMarkets;
    final state = _independentState;
    if (service == null || state == null || state.mode != mode ||
        state.player.marginMode == marginMode) return;
    _independentOperate(() async {
      final selected = await service.setPlayerMarginMode(
          mode: mode, marginMode: marginMode);
      _marketRepaint.value++;
      return '${state.profile.label}保证金模式已切换为${selected.label} · '
          '只对下一次开仓生效';
    });
  }

  void _independentOperate(Future<String> Function() operation) {
    if (!_ready || _busy || _independentMarkets == null) return;
    if (_auto) _pause();
    setState(() => _busy = true);
    final task = _performIndependent(operation);
    _operation = task;
    unawaited(task.then<void>((_) {
      if (identical(_operation, task)) _operation = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_operation, task)) _operation = null;
    }));
  }

  Future<void> _performIndependent(Future<String> Function() operation) async {
    try {
      final notice = await operation();
      if (mounted) setState(() => _notice = notice);
    } catch (error) {
      _pause();
      if (mounted) setState(() {
        _independentFault = '独立市场操作失败，已停止运行：$error';
        _fault = _independentFault;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _independentRiskTerms(TxIndependentMarketState state, String symbol) {
    final profile = state.profile;
    final instrument = profile.instruments.firstWhere(
        (item) => item.symbol == symbol);
    final usesMargin = instrument.usesMargin;
    final baseRule = TxMarketRiskRules.forMode(state.mode);
    final rule = state.player.riskRule(symbol);
    final mark = state.markPriceCents(symbol);
    final required = state.player.requiredEntryCents(
        symbol: symbol, priceCents: mark, quantity: 1);
    final activePlayerOrders = state.runtime.venue.activeOrders.where(
        (order) => order.ownerId == TxIndependentMarketState.playerId).length;
    final canChange = !state.playerRisk.hasPositions && activePlayerOrders == 0;
    final latestSettlement = state.lastSettlement?.settlements[
        TxIndependentMarketState.playerId];
    final carrying = !instrument.usesMargin
        ? '现货现金交收 · 不使用融资/杠杆'
        : switch (state.mode) {
            TxMarketMode.usEquity =>
              '融资 ${baseRule.financingBpsPerDay} bp/日（多头借入部分）'
                  ' · 空头借券 ${baseRule.shortBorrowBpsPerDay} bp/日',
            TxMarketMode.futures =>
              '每日盯市 · 维持保证金 ${rule.maintenanceMarginBps / 100}%'
                  ' · ${profile.settlement}',
            TxMarketMode.crypto => 'BTC 永续资金费率 '
                '${baseRule.fundingBpsPerDay} bp/日（多空方向结算）',
            TxMarketMode.forex => '展期 '
                '${baseRule.rolloverBpsPerDay} bp/日（按持仓名义）',
            TxMarketMode.aShare => '现货现金交收',
          };
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.tune_rounded, size: 17,
              color: TxTerminalColors.cyan),
          const SizedBox(width: 6),
          const Expanded(child: Text('杠杆与融资规则',
              style: TextStyle(fontWeight: FontWeight.w700))),
          Text('${state.player.leverageMultiple}×',
              style: const TextStyle(color: TxTerminalColors.cyan,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 5),
        Text('${instrument.kind} · ${instrument.contractMultiplier} · $carrying',
            style: const TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
        const SizedBox(height: 6),
        Text(instrument.usesMargin
            ? '当前杠杆占用初始保证金 ${(rule.initialMarginBps / 100).toStringAsFixed(2)}%'
                ' · 按当前标记一${instrument.orderUnit}约占 ${_quoteAmount(profile, required)}'
            : '当前标记一${instrument.orderUnit}需要现金 ${_quoteAmount(profile, required)}',
            style: const TextStyle(fontSize: 11)),
        if (instrument.usesMargin) ...[
          const SizedBox(height: 7),
          const Text('账户杠杆（只对新开仓生效；已有持仓必须先平仓）',
              style: TextStyle(fontSize: 10, color: Colors.white70)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final multiple in TxMarketRiskRules.leverageOptions(state.mode))
              ChoiceChip(
                label: Text('${multiple}×'),
                selected: state.player.leverageMultiple == multiple,
                onSelected: canChange
                    ? (_) => _changeIndependentLeverage(state.mode, multiple)
                    : null,
              ),
          ]),
          if (!canChange)
            const Text('当前有持仓或未成交委托，先平仓/撤单后才能调整杠杆。',
                style: TextStyle(fontSize: 10, color: Colors.amberAccent)),
        ],
        if (baseRule.usesMargin) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('保证金模式',
                style: TextStyle(fontSize: 10, color: Colors.white70))),
            Text(state.player.marginMode.label,
                style: const TextStyle(color: TxTerminalColors.cyan,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final mode in TxMarginMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: state.player.marginMode == mode,
                onSelected: canChange
                    ? (_) => _changeIndependentMarginMode(state.mode, mode)
                    : null,
              ),
          ]),
          Text(state.player.marginMode.description,
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
          if (!canChange)
            const Text('保证金模式与杠杆一样，必须先平仓并撤销未成交委托。',
                style: TextStyle(fontSize: 10, color: Colors.amberAccent)),
        ],
        const SizedBox(height: 4),
        const Text('资金、保证金、费用、日结和资金费率均进入独立账户快照；不会把标记价冒充成交。',
            style: TextStyle(fontSize: 10, color: Colors.white54)),
        if (latestSettlement != null) ...[
          const SizedBox(height: 7),
          Text('最近日结 ${latestSettlement.fromGameDay}→${latestSettlement.toGameDay}日'
              ' · 盯市 ${_quoteAmount(profile, latestSettlement.markToMarketPnlCents)}'
              ' · ${state.mode == TxMarketMode.futures ? '日结/融资' : '融资/资金费率'} '
              '${_quoteAmount(profile, latestSettlement.financingPnlCents)}',
              style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
        ],
      ]),
    ));
  }

  /// A review is separate from an order. Entering review pauses the visual
  /// clock, and revision + input fields must still match at confirmation.
  void _confirmTicket() {
    if (_independentMode) {
      _confirmIndependentTicket();
      return;
    }
    if (!_tradingReady) {
      setState(() => _notice = '当前交易核心尚未就绪，请等待市场校验完成后重试');
      return;
    }
    final sessionStatus = TxSession.marketSessionStatusAt(
        committedStep: _trader!.current.session.step,
        fractionalSeconds: _clockSeconds.floor());
    if (!sessionStatus.isOpen) {
      setState(() => _notice = 'A股${sessionStatus.label}，交易入口已锁定；开市后可继续下单');
      return;
    }
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
        priceText: priceText, timeInForce: _timeInForce);
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
          Text(limited
              ? '委托类型：限价单 · ${_timeInForce.label}'
              : '委托类型：市价单'),
          Text('委托数量：$quantity 股'),
          Text(limited ? '限价：¥${money(limitPrice!)}'
              : '参考盘口价格：${referencePrice == null ? '暂无对手盘' : '¥${money(referencePrice)}'}'),
          Text('参考名义金额：${indicative == null ? '无法估算' : '约 ¥${money(indicative)}'}'),
          Text('存档修订：r$revision'),
          const SizedBox(height: 8),
          const Text('模拟交易：市价单可能跨档滑点或无法全部成交；'
              'Post Only 只做 Maker，IOC 允许部分成交后撤销，FOK 深度不足时整单取消；'
              '参考价格不是最终成交承诺。',
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
          if (!_tradingReady || !review.isStillCurrent(
              revision: _trader!.current.revision, symbol: _symbolName,
              side: _ticketSide, limited: _limit,
              quantityText: _qty.text.trim(), priceText: _price.text.trim(),
              timeInForce: _timeInForce)) {
            setState(() => _notice = '存档修订或下单参数已变化；请重新检查，不执行旧委托');
            return;
          }
          _trade(side);
        }, child: Text('确认${side == TxSide.buy ? '买入' : '卖出'}')),
      ],
    ));
  }

  Widget _chooseIndependentSymbol(TxIndependentMarketState state) {
    final profile = state.profile;
    final selected = _symbol.clamp(0, profile.instruments.length - 1).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          segments: [
            for (var i = 0; i < profile.instruments.length; i++)
              ButtonSegment<int>(
                value: i,
                label: Text(profile.instruments[i].symbol),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (values) => setState(() {
            _symbol = values.first;
            _reduceOnly = false;
            _price.text = (state.markPriceCents(
                    profile.instruments[_symbol].symbol) / 100)
                .toStringAsFixed(2);
          }),
        ),
      ),
    );
  }

  Widget _independentTrading(TxSession session) {
    final state = _independentState;
    if (_independentLoading || state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final profile = state.profile;
    final index = _symbol.clamp(0, profile.instruments.length - 1).toInt();
    final instrument = profile.instruments[index];
    final symbol = instrument.symbol;
    final status = state.sessionStatus;
    final canTrade = _tradingReady && status.isOpen;
    final risk = state.playerRisk;
    final asks = state.runtime.venue.depth(symbol, TxSide.sell);
    final bids = state.runtime.venue.depth(symbol, TxSide.buy);
    final active = state.runtime.venue.activeOrders
        .where((order) => order.ownerId == TxIndependentMarketState.playerId)
        .toList();
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    Widget reviewButton() => TxTicketSubmitBar(
        side: _ticketSide,
        isLimit: _limit,
        timeInForce: _timeInForce,
        enabled: canTrade,
        onReview: _confirmTicket,
      );
    return Column(children: [
      Expanded(child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        children: [
          _pageHeader(
            icon: Icons.swap_horiz_rounded,
            eyebrow: 'ORDER DESK',
            title: '交易委托',
            subtitle: '${profile.label} · 独立账户 · ${profile.quoteCurrency} · 先看盘口，再确认订单。',
            status: canTrade ? '可下单 · 真实订单簿' : '休市 · 入口锁定',
            accent: canTrade ? TxTerminalColors.buy : TxTerminalColors.gold,
          ),
          _marketContextBar(session),
          if (!status.isOpen)
            Card(child: ListTile(
              dense: true,
              leading: Icon(status.isBreak ? Icons.pause_circle_outline :
                  Icons.event_busy, color: Colors.amberAccent),
              title: Text('当前${status.label}'),
              subtitle: const Text('订单入口已锁定；未成交 GTC 委托保留到下一开市边界。'),
            )),
          _chooseIndependentSymbol(state),
          _independentRiskTerms(state, symbol),
          _title('订单参数', sub: '选择方向、订单类型、数量和有效方式；确认前不会冻结资金。'),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              SizedBox(width: double.infinity,
                child: SegmentedButton<TxSide>(
                  segments: const [
                    ButtonSegment(value: TxSide.buy, label: Text('买入 Buy'),
                        icon: Icon(Icons.trending_up)),
                    ButtonSegment(value: TxSide.sell, label: Text('卖出 Sell'),
                        icon: Icon(Icons.trending_down)),
                  ],
                  selected: {_ticketSide},
                  onSelectionChanged: !canTrade ? null :
                      (values) => setState(() => _ticketSide = values.first),
                )),
              if (instrument.usesMargin ||
                  (risk.positions[symbol]?.availableToClose ?? 0) > 0) ...[
                const SizedBox(height: 3),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('只减仓 · Reduce-only'),
                  subtitle: Text(_reduceOnly
                      ? '只允许减少当前净仓，不会反向开仓；适合分批止盈、止损或降低强平风险。'
                      : '关闭时按普通委托处理，可能开仓、加仓或反向开仓。'),
                  value: _reduceOnly,
                  onChanged: canTrade
                      ? (value) => setState(() => _reduceOnly = value)
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(children: [
                _metric('现金', _quoteAmount(profile, risk.cashCents)),
                _metric('可用保证金', _quoteAmount(profile, risk.freeMarginCents)),
                _metric('卖一', asks.isEmpty ? '—' :
                    _quotePrice(profile, asks.first.priceCents)),
                _metric('买一', bids.isEmpty ? '—' :
                    _quotePrice(profile, bids.first.priceCents)),
              ]),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('市价 Market'),
                        icon: Icon(Icons.bolt_outlined)),
                    ButtonSegment(value: true, label: Text('限价 Limit'),
                        icon: Icon(Icons.tune)),
                  ],
                  selected: {_limit},
                  onSelectionChanged: !canTrade ? null : (values) => setState(() {
                    _limit = values.first;
                    if (!_limit) _timeInForce = TxTimeInForce.gtc;
                  }),
                )),
              if (_limit) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: SegmentedButton<TxTimeInForce>(
                    segments: const [
                      ButtonSegment(value: TxTimeInForce.gtc, label: Text('GTC')),
                      ButtonSegment(value: TxTimeInForce.postOnly,
                          label: Text('Post Only')),
                      ButtonSegment(value: TxTimeInForce.ioc, label: Text('IOC')),
                      ButtonSegment(value: TxTimeInForce.fok, label: Text('FOK')),
                    ],
                    selected: {_timeInForce},
                    onSelectionChanged: !canTrade ? null :
                        (values) => setState(() => _timeInForce = values.first),
                  )),
                const SizedBox(height: 4),
                Text(
                  switch (_timeInForce) {
                    TxTimeInForce.gtc => 'GTC：剩余数量留在本地订单簿。',
                    TxTimeInForce.postOnly => 'Post Only：会吃掉对手盘时整单拒绝。',
                    TxTimeInForce.ioc => 'IOC：允许部分成交，剩余立即撤销。',
                    TxTimeInForce.fok => 'FOK：深度不足时整单取消。',
                  },
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
              if (_limit) Wrap(spacing: 6, children: [
                ActionChip(label: const Text('卖一'), onPressed: asks.isEmpty ||
                    !canTrade ? null : () => _price.text =
                    (asks.first.priceCents / 100).toStringAsFixed(2)),
                ActionChip(label: const Text('买一'), onPressed: bids.isEmpty ||
                    !canTrade ? null : () => _price.text =
                    (bids.first.priceCents / 100).toStringAsFixed(2)),
              ]),
              const Align(alignment: Alignment.centerLeft,
                  child: Text('快捷数量', style: TextStyle(color: Colors.white70))),
              Wrap(spacing: 5, children: [
                for (final amount in const [1, 10, 100, 500])
                  ActionChip(label: Text('$amount ${instrument.orderUnit}'),
                      onPressed: canTrade ? () => _qty.text = '$amount' : null),
              ]),
              const SizedBox(height: 5),
              Wrap(spacing: 5, children: [
                for (final percent in const [25, 50, 75, 100])
                  ActionChip(label: Text('$percent%'),
                      onPressed: canTrade ? () =>
                          _applyIndependentTicketPercent(state, percent) : null),
              ]),
              const SizedBox(height: 6),
              TextField(controller: _qty, enabled: canTrade,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: '委托数量（${instrument.orderUnit}）',
                    border: const OutlineInputBorder())),
              if (_limit) ...[
                const SizedBox(height: 10),
                TextField(controller: _price, enabled: canTrade,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: '限价（${profile.quoteCurrency}）',
                      border: const OutlineInputBorder())),
              ],
              const SizedBox(height: 9),
              if (!_limit) Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: canTrade ? () =>
                      _showIndependentMarketEstimate(state, TxSide.buy) : null,
                  icon: const Icon(Icons.calculate_outlined, size: 17),
                  label: const Text('试算买入'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: canTrade ? () =>
                      _showIndependentMarketEstimate(state, TxSide.sell) : null,
                  icon: const Icon(Icons.calculate_outlined, size: 17),
                  label: const Text('试算卖出'))),
              ]),
              if (keyboardOpen) reviewButton(),
            ]),
          )),
          if (active.isNotEmpty) Card(child: ExpansionTile(
            title: Text('活动委托（${active.length}）'),
            subtitle: const Text('独立市场未成交委托；点击撤单只影响当前板块'),
            children: [for (final order in active) ListTile(
              dense: true,
              title: Text('${order.symbol} · ${order.side == TxSide.buy ? '买' : '卖'} '
                  '${order.remaining}/${order.quantity}'),
              subtitle: Text('${order.id} · ${order.timeInForce.label}'
                  '${order.reduceOnly ? ' · 只减仓' : ''}'),
              trailing: IconButton(
                tooltip: '撤单',
                icon: const Icon(Icons.close),
                onPressed: _ready ? () => _cancelIndependent(order.id) : null,
              ),
            )],
          )),
          _independentDepth(state, symbol, allowTicket: true),
        ],
      )),
      if (!keyboardOpen) reviewButton(),
    ]);
  }

  Widget _trading(TxSession session) {
    if (_independentMode) return _independentTrading(session);
    final profile = TxMarketProfile.of(_marketMode);
    final canTrade = _tradingReady && session.marketSessionStatus.isOpen;
    final account = session.engine.account(TxSession.playerId);
    final ask = session.engine.depth(_symbolName, TxSide.sell);
    final bid = session.engine.depth(_symbolName, TxSide.buy);
    final active = session.activePlayerOrders;
    // Keep the review button within thumb reach while chart/order ticket
    // content scrolls. During text entry, show the same button in the list
    // instead of covering the Android keyboard.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    Widget reviewButton() => TxTicketSubmitBar(side: _ticketSide,
        isLimit: _limit, timeInForce: _timeInForce,
        enabled: canTrade, onReview: _confirmTicket);
    return Column(children: [
      Expanded(child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14), children: [
      _pageHeader(
        icon: Icons.swap_horiz_rounded,
        eyebrow: 'ORDER DESK',
        title: '交易委托',
        subtitle: '${profile.label} · 先核对可用资金、盘口和滑点，再提交真实订单。',
        status: canTrade ? '可下单 · 真实订单簿' : '休市 · 入口锁定',
        accent: canTrade ? TxTerminalColors.buy : TxTerminalColors.gold,
      ),
      _marketContextBar(session),
      if (!session.marketSessionStatus.isOpen)
        Card(child: ListTile(
          dense: true,
          leading: Icon(session.marketSessionStatus.isBreak
              ? Icons.pause_circle_outline : Icons.event_busy,
              color: Colors.amberAccent),
          title: Text('当前${session.marketSessionStatus.label}'),
          subtitle: const Text('交易入口已锁定；玩家 GTC 委托保留，开市后再参与撮合。'),
        )),
      _chooseSymbol(session),
      _title('订单参数', sub: '选择方向、订单类型、数量和有效方式；确认前不会冻结资金。'),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        SizedBox(width: double.infinity, child: SegmentedButton<TxSide>(
          segments: const [
            ButtonSegment(value: TxSide.buy, label: Text('买入 Buy'),
                icon: Icon(Icons.trending_up)),
            ButtonSegment(value: TxSide.sell, label: Text('卖出 Sell'),
                icon: Icon(Icons.trending_down)),
          ], selected: {_ticketSide},
          onSelectionChanged: !canTrade ? null :
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
          onSelectionChanged: !canTrade ? null :
              (values) => setState(() {
                _limit = values.first;
                if (!_limit) _timeInForce = TxTimeInForce.gtc;
              }))),
        if (_limit) ...[
          const SizedBox(height: 8),
          const Align(alignment: Alignment.centerLeft,
              child: Text('限价生效方式', style: TextStyle(color: Colors.white70))),
          const SizedBox(height: 5),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: SegmentedButton<TxTimeInForce>(
              segments: const [
                ButtonSegment(value: TxTimeInForce.gtc, label: Text('GTC')),
                ButtonSegment(value: TxTimeInForce.postOnly,
                    label: Text('Post Only')),
                ButtonSegment(value: TxTimeInForce.ioc, label: Text('IOC')),
                ButtonSegment(value: TxTimeInForce.fok, label: Text('FOK')),
              ],
              selected: {_timeInForce},
              onSelectionChanged: !canTrade ? null :
                  (values) => setState(() => _timeInForce = values.first))),
          const SizedBox(height: 4),
          Text(
            switch (_timeInForce) {
              TxTimeInForce.gtc => '普通限价：成交后剩余挂在订单簿中，直到成交或撤单。',
              TxTimeInForce.postOnly => '只做 Maker：若会立即吃掉对手盘，则整单拒绝。',
              TxTimeInForce.ioc => '立即成交或取消：允许部分成交，剩余立即取消。',
              TxTimeInForce.fok => '全部成交或取消：深度不足时不产生任何成交。',
            },
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ],
        if (_limit) Wrap(spacing: 6, children: [
          ActionChip(label: const Text('卖一价'),
            onPressed: ask.isEmpty || !canTrade ? null : () =>
                _price.text = money(ask.first.priceCents)),
          ActionChip(label: const Text('买一价'),
            onPressed: bid.isEmpty || !canTrade ? null : () =>
                _price.text = money(bid.first.priceCents)),
        ]),
        const Align(alignment: Alignment.centerLeft,
            child: Text('快捷数量', style: TextStyle(color: Colors.white70))),
        Wrap(spacing: 5, runSpacing: 0, children: [
          for (final amount in [1, 10, 100, 500])
            ActionChip(label: Text('$amount股'),
              onPressed: canTrade ? () => _qty.text = '$amount' : null),
        ]),
        const SizedBox(height: 5),
        const Align(alignment: Alignment.centerLeft,
            child: Text('使用可用资产比例 · 参考价估算',
              style: TextStyle(color: Colors.white70, fontSize: 12))),
        Wrap(spacing: 5, children: [
          for (final percent in [25, 50, 75, 100])
            ActionChip(label: Text('$percent%'),
              onPressed: !canTrade ? null :
                  () => _applyTicketPercent(session, percent)),
        ]),
        const SizedBox(height: 6),
        TextField(controller: _qty, enabled: canTrade,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '委托股数',
              border: OutlineInputBorder())),
        if (_limit) ...[
          const SizedBox(height: 10),
          TextField(controller: _price, enabled: canTrade,
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
              onPressed: canTrade ? () => _showMarketEstimate(TxSide.buy) : null,
              icon: const Icon(Icons.calculate_outlined, size: 17),
              label: const Text('试算买入'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: canTrade ? () => _showMarketEstimate(TxSide.sell) : null,
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
          subtitle: Text('${order.id} · ${order.timeInForce.label} · '
              '¥${money(order.limitPriceCents!)}'),
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
    if (_independentMode) return _independentAssets();
    final account = session.engine.account(TxSession.playerId);
    final holdings = _positionsForRevision(session, saved.revision);
    // Concentration/liquidity diagnostics are intentionally anchored to the
    // last durable account snapshot; live mark-to-market remains below.
    final risk = TxPortfolioRisk.compute(_trader!.durableCurrent.session);
    final reliable = holdings.values.every((p) => p.costKnown);
    final unrealized = holdings.values.fold<int>(0,
        (total, p) => total + p.unrealizedPnlCents);
    final realized = holdings.values.fold<int>(0,
        (total, p) => total + p.realizedPnlCents);
    Widget pnlValue(String label, int amount) =>
      _metric(label, signedMoney(amount));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _pageHeader(
        icon: Icons.account_balance_wallet_rounded,
        eyebrow: 'PORTFOLIO',
        title: '资金与资产',
        subtitle: '先看权益与现金，再看风险、压力测试和每个标的的成本收益。',
        status: saved.pending ? '有待保存状态' : 'SQLite 已落盘',
        accent: saved.pending ? TxTerminalColors.gold : TxTerminalColors.primary,
      ),
      _marketContextBar(session),
      _title('账户总览', sub: '开市低倍率时估值随指示价变动；现金与已实现收益只按真实成交结算'),
      ValueListenableBuilder<double>(valueListenable: _seconds,
        builder: (context, seconds, _) {
          final valuationSeconds = _marketPreviewAllowed(session, seconds)
              ? seconds : 0.0;
          final mark = TxLivePortfolioValuation.evaluate(
              session, holdings, valuationSeconds);
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
      _title('仓位风险仪表盘', sub: saved.pending
          ? '按 SQLite 已落盘资产分析；当前行情候选只影响下方实时估值'
          : '仅分析已提交资产；参考阈值用于模拟游戏，不发出交易指令'),
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
                final valuationSeconds = _marketPreviewAllowed(session, seconds)
                    ? seconds : 0.0;
                final mark = TxLivePortfolioValuation.evaluate(
                    session, holdings, valuationSeconds);
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
      /*
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
            '检查点只是恢复加速；自动保存周期另行设置。玩家交易仍立即原子提交。',
            style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]))),
      _title('自动保存周期', sub: '降低连续行情的 SQLite 写入频率；显示中的待保存状态不会伪装成已落盘'),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('当前：每 $_automaticSaveMinutes 个游戏分钟自动保存',
            style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('选择：每 $_automaticSaveDraft 个游戏分钟',
            style: const TextStyle(color: TxTerminalColors.secondaryText)),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final minutes in const [1, 5, 15, 30, 60])
              ChoiceChip(label: Text('$minutes 分钟'),
                selected: _automaticSaveDraft == minutes,
                onSelected: _ready
                  ? (_) => setState(() => _automaticSaveDraft = minutes)
                  : null),
          ]),
          const SizedBox(height: 9),
          FilledButton.icon(onPressed: _ready &&
              _automaticSaveDraft != _automaticSaveMinutes
                ? _saveAutomaticSaveMinutes : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存自动保存周期')),
          const SizedBox(height: 6),
          const Text('自动行情最多保留到最近一次保存的状态；崩溃时可能丢失未保存的模拟分钟，'
            '但不会破坏已保存的 SQLite 链。玩家下单、切后台和退出前会强制保存。',
            style: TextStyle(fontSize: 11, color: Colors.white60)),
        ]))),
      */
      _title('存档状态'),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('修订 ${saved.revision} · 模拟步数 ${session.step}'),
          if (saved.pending)
            Text('当前内存状态待保存 ${saved.pendingOperations} 项、'
                '${_trader!.pendingGameMinutes}/$_automaticSaveMinutes 个游戏分钟 · '
                'SQLite 仍为 r${saved.revision}',
              style: const TextStyle(color: TxTerminalColors.primary)),
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

  Widget _independentAssets() {
    final state = _independentState;
    if (_independentLoading || state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final profile = state.profile;
    final risk = state.playerRisk;
    return ListView(padding: const EdgeInsets.all(14), children: [
      _pageHeader(
        icon: Icons.account_balance_wallet_rounded,
        eyebrow: 'PORTFOLIO',
        title: '资金与资产',
        subtitle: '${profile.label} · 独立账户与 A 股完全隔离，风险只按本板块真实成交计算。',
        status: '独立账户 · CAS r${state.sequence}',
        accent: TxTerminalColors.gold,
      ),
      _marketContextBar(_trader!.current.session),
      _title('账户总览', sub: '现金、保证金、持仓与已实现收益按本市场单独统计'),
      Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(children: [
          _metric('权益', _quoteAmount(profile, risk.equityCents)),
          _metric('现金', _quoteAmount(profile, risk.cashCents)),
          _metric('可用保证金', _quoteAmount(profile, risk.freeMarginCents)),
          _metric('已用保证金', _quoteAmount(profile, risk.usedMarginCents)),
          _metric('保证金模式', risk.marginMode.label),
          _metric('未实现盈亏', _quoteAmount(profile, risk.unrealizedPnlCents)),
          _metric('已实现盈亏', _quoteAmount(profile, risk.realizedPnlCents)),
        ]),
      )),
      Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('保证金风险',
                style: TextStyle(fontWeight: FontWeight.w700))),
            if (risk.marginMode != TxMarginMode.cross)
              Text(risk.marginMode.label,
                  style: const TextStyle(color: TxTerminalColors.cyan,
                      fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          if (risk.marginRatio == null)
            const Text('当前无保证金持仓', style: TextStyle(color: Colors.white70))
          else ...[
            Text('${risk.marginMode == TxMarginMode.isolated ? '最小逐仓' : '账户'}'
                '维持保证金率 ${(risk.marginRatio! * 100).toStringAsFixed(1)}%'),
            LinearProgressIndicator(
                value: (risk.marginRatio! / 4).clamp(0.0, 1.0).toDouble(),
                minHeight: 5),
            const SizedBox(height: 5),
            Text('已用保证金 ${_quoteAmount(profile, risk.usedMarginCents)} · '
                '${risk.marginMode == TxMarginMode.isolated ? '逐仓已分配' : '账户共享'} '
                '${_quoteAmount(profile, risk.isolatedMarginCents)}'),
            if (risk.liquidationBufferCents != null)
              Text('距维持保证金 ${_quoteAmount(profile, risk.liquidationBufferCents!)}',
                  style: TextStyle(
                      color: risk.liquidationBufferCents! <= 0
                          ? red : TxTerminalColors.secondaryText)),
          ],
          if (risk.liquidationRequired)
            const Text('保证金不足：只允许通过真实对手盘减仓或强平',
                style: TextStyle(color: red)),
          const SizedBox(height: 4),
          const Text('估值只使用独立市场已保存标记；不会把指示价当成成交或现金。',
              style: TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
      )),
      _independentRiskTerms(state, profile.instruments[
          _symbol.clamp(0, profile.instruments.length - 1).toInt()].symbol),
      _independentConditionalOrders(state),
      _title('独立市场持仓', sub: '移动加权成本 · 真实成交费用已计入账户核心'),
      for (final instrument in profile.instruments)
        _independentPositionCard(state, instrument.symbol),
    ]);
  }

  void _prepareIndependentReduceOnly(
      TxIndependentMarketState state, String symbol, int percent) {
    final position = state.playerRisk.positions[symbol];
    if (position == null || position.isFlat || position.availableToClose < 1) {
      return;
    }
    final index = state.profile.instruments.indexWhere(
        (item) => item.symbol == symbol);
    if (index < 0) return;
    final available = position.availableToClose;
    final quantity = math.max(1, (available * percent + 99) ~/ 100);
    final mark = state.markPriceCents(symbol);
    setState(() {
      _marketMode = state.mode;
      _symbol = index;
      _page = 1;
      _ticketSide = position.netQuantity > 0 ? TxSide.sell : TxSide.buy;
      _limit = false;
      _timeInForce = TxTimeInForce.gtc;
      _reduceOnly = true;
      _qty.text = '$quantity';
      _price.text = (mark / 100).toStringAsFixed(2);
      _notice = '${state.profile.label}已填入只减仓 $quantity/$available '
          '${state.profile.instruments[index].orderUnit}，确认前不会提交';
    });
  }

  int _conditionalDefaultTrigger(TxIndependentMarketState state, String symbol,
      TxSide side, TxMarketConditionalOrderKind kind) {
    final mark = state.markPriceCents(symbol);
    final rule = state.player.riskRule(symbol);
    int alignDown(int value) => math.max(rule.tickSizeCents,
        (value ~/ rule.tickSizeCents) * rule.tickSizeCents);
    int alignUp(int value) => math.max(rule.tickSizeCents,
        ((value + rule.tickSizeCents - 1) ~/ rule.tickSizeCents) *
            rule.tickSizeCents);
    final down = alignDown((mark * 98) ~/ 100);
    final up = alignUp((mark * 102 + 99) ~/ 100);
    if (kind == TxMarketConditionalOrderKind.stopLoss) {
      return side == TxSide.sell ? down : up;
    }
    return side == TxSide.sell ? up : down;
  }

  int? _conditionalPriceCents(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d{1,10}(\.\d{1,4})?$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('.');
    final fractional = parts.length == 1 ? '' : parts[1];
    // The engine stores cents. Forex displays four decimals for readability,
    // but its current tick is still one cent, so extra digits must be zero.
    if (fractional.length > 2 &&
        fractional.substring(2).contains(RegExp(r'[1-9]'))) {
      return null;
    }
    final normalizedFraction = fractional.padRight(2, '0').substring(0, 2);
    final normalized = normalizedFraction.isEmpty
        ? parts.first
        : '${parts.first}.$normalizedFraction';
    return _cents(normalized);
  }

  String _conditionalPriceText(TxMarketProfile profile, int cents) =>
      (cents / 100).toStringAsFixed(
          profile.mode == TxMarketMode.forex ? 4 : 2);

  Future<void> _showIndependentConditionalDialog(
      TxIndependentMarketState state, String symbol) async {
    final position = state.playerRisk.positions[symbol];
    final available = position?.availableToClose ?? 0;
    if (position == null || position.isFlat || available < 1) {
      if (mounted) {
        setState(() => _notice = '$symbol 当前没有可设置保护单的可平仓位');
      }
      return;
    }
    final profile = state.profile;
    final side = position.netQuantity > 0 ? TxSide.sell : TxSide.buy;
    final sequence = state.sequence;
    var kind = TxMarketConditionalOrderKind.stopLoss;
    final triggerController = TextEditingController(
      text: _conditionalPriceText(profile,
          _conditionalDefaultTrigger(state, symbol, side, kind)));
    final quantityController = TextEditingController(text: '$available');
    String? error;
    final draft = await showDialog<_TxConditionalDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final trigger = _conditionalPriceCents(triggerController.text);
            final quantity = int.tryParse(quantityController.text.trim());
            if (trigger == null || quantity == null || quantity < 1) {
              setDialogState(() => error = '请输入有效的触发价和数量');
              return;
            }
            try {
              state.player.riskRule(symbol).validatePrice(trigger);
              state.player.riskRule(symbol).validateQuantity(quantity);
            } on Object catch (failure) {
              setDialogState(() => error = '$failure');
              return;
            }
            if (quantity > available) {
              setDialogState(() => error = '数量不能超过当前可平 $available');
              return;
            }
            Navigator.of(dialogContext).pop(_TxConditionalDraft(
              kind: kind,
              triggerPriceCents: trigger,
              quantity: quantity,
            ));
          }

          return AlertDialog(
            title: Text('$symbol · 设置保护单'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前方向：${side == TxSide.sell ? '多头保护 · 触发卖出' : '空头保护 · 触发买入'}'),
                  Text('当前标记 ${_quotePrice(profile, state.markPriceCents(symbol))} · '
                      '最多可平 $available ${profile.instruments.firstWhere(
                          (item) => item.symbol == symbol).orderUnit}'),
                  const SizedBox(height: 10),
                  SegmentedButton<TxMarketConditionalOrderKind>(
                    segments: const [
                      ButtonSegment(
                        value: TxMarketConditionalOrderKind.stopLoss,
                        label: Text('止损'),
                        icon: Icon(Icons.shield_outlined),
                      ),
                      ButtonSegment(
                        value: TxMarketConditionalOrderKind.takeProfit,
                        label: Text('止盈'),
                        icon: Icon(Icons.flag_outlined),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (values) {
                      final next = values.first;
                      setDialogState(() {
                        kind = next;
                        triggerController.text = _conditionalPriceText(
                            profile,
                            _conditionalDefaultTrigger(
                                state, symbol, side, next));
                        error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: triggerController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: '触发价',
                      helperText: '按已保存标记价判断；触发后以只减仓市价单入场',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '减仓数量',
                      suffixText: profile.instruments
                          .firstWhere((item) => item.symbol == symbol)
                          .orderUnit,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: red)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: submit,
                icon: const Icon(Icons.add_task),
                label: const Text('保存保护单'),
              ),
            ],
          );
        },
      ),
    );
    triggerController.dispose();
    quantityController.dispose();
    if (!mounted || draft == null) return;
    final current = _independentState;
    if (current == null || current.mode != state.mode ||
        current.sequence != sequence) {
      setState(() => _notice = '市场快照已变化，保护单未保存，请重新确认');
      return;
    }
    final service = _independentMarkets;
    if (service == null) return;
    _independentOperate(() async {
      final order = await service.placeConditional(
        mode: state.mode,
        symbol: symbol,
        kind: draft.kind,
        triggerPriceCents: draft.triggerPriceCents,
        quantity: draft.quantity,
        gameDay: state.runtime.gameDay,
        minuteOfDay: state.runtime.minuteOfDay,
      );
      _marketRepaint.value++;
      return '${order.kind.label}已保存：${order.triggerOperator} '
          '${_quotePrice(profile, order.triggerPriceCents)} · '
          '${order.quantity} ${profile.instruments.firstWhere(
              (item) => item.symbol == symbol).orderUnit} · CAS r${state.sequence}';
    });
  }

  Widget _independentConditionalOrders(TxIndependentMarketState state) {
    final profile = state.profile;
    final orders = state.runtime.conditionalOrders;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: orders.isNotEmpty,
        leading: Icon(
          orders.isEmpty ? Icons.shield_outlined : Icons.shield,
          color: orders.isEmpty ? TxTerminalColors.secondaryText :
              TxTerminalColors.cyan,
        ),
        title: Text('保护单 · ${orders.length}'),
        subtitle: Text(orders.isEmpty
            ? '暂无止盈/止损；触发后会进入真实订单簿并只减仓'
            : '以已保存标记价触发 · 触发后自动市价减仓'),
        children: [
          if (orders.isEmpty)
            const ListTile(
              dense: true,
              title: Text('在持仓卡中选择“设置保护单”'),
            ),
          for (final order in orders)
            ListTile(
              dense: true,
              title: Text('${order.kind.label} · ${order.symbol} · '
                  '${order.side == TxSide.sell ? '卖出' : '买入'}'),
              subtitle: Text('${order.triggerOperator} '
                  '${_quotePrice(profile, order.triggerPriceCents)} · '
                  '数量 ${order.quantity} · 当前标记 '
                  '${_quotePrice(profile, state.markPriceCents(order.symbol))}'),
              trailing: IconButton(
                tooltip: '取消保护单',
                icon: const Icon(Icons.delete_outline),
                onPressed: _ready && !_busy
                    ? () => _cancelIndependentConditional(order.id)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _independentPositionCard(TxIndependentMarketState state,
      String symbol) {
    final position = state.playerRisk.positions[symbol];
    final profile = state.profile;
    final risk = state.playerRisk;
    final mark = state.markPriceCents(symbol);
    final instrument = profile.instruments.firstWhere(
        (item) => item.symbol == symbol);
    final usesMargin = instrument.usesMargin;
    final quantity = position?.netQuantity ?? 0;
    final unrealized = position == null || position.isFlat
        ? 0
        : (mark - position.averageEntryCents) * position.netQuantity *
            instrument.contractMultiplierUnits;
    final hasPosition = position != null && !position.isFlat;
    final positionRule = state.player.riskRule(symbol);
    final notional = hasPosition
        ? mark * position!.netQuantity.abs() * instrument.contractMultiplierUnits
        : 0;
    final entryNotional = hasPosition
        ? position!.averageEntryCents * position.netQuantity.abs() *
            instrument.contractMultiplierUnits
        : 0;
    final pnlPercent = entryNotional == 0
        ? 0.0 : unrealized * 100 / entryNotional;
    final breakeven = hasPosition
        ? _independentBreakevenCents(state, position!) : null;
    final liquidation = hasPosition
        ? state.player.estimatedLiquidationPriceCents(symbol) : null;
    final maintenance = hasPosition
        ? positionRule.maintenanceMarginCents(
            priceCents: mark, quantity: position!.netQuantity.abs())
        : 0;
    final marginBalance = hasPosition && usesMargin &&
            risk.marginMode == TxMarginMode.isolated
        ? position!.isolatedMarginCents + unrealized : null;
    final marginBase = hasPosition && usesMargin
        ? risk.marginMode == TxMarginMode.isolated
            ? position!.isolatedMarginCents
            : positionRule.initialMarginCents(
                priceCents: mark, quantity: position!.netQuantity.abs())
        : 0;
    final marginRoi = marginBase == 0 ? 0.0 : unrealized * 100 / marginBase;
    final positionBuffer = hasPosition && usesMargin
        ? risk.marginMode == TxMarginMode.isolated
            ? marginBalance! - maintenance
            : risk.liquidationBufferCents
        : null;
    final conditionalOrders = state.runtime.conditionalOrders
        .where((order) => order.symbol == symbol)
        .toList(growable: false);
    final riskColor = positionBuffer == null
        ? TxTerminalColors.secondaryText
        : positionBuffer <= 0
            ? red
            : positionBuffer < maintenance ~/ 4 ? TxTerminalColors.gold : green;
    String signedQuote(int cents) => cents > 0
        ? '+${_quoteAmount(profile, cents)}'
        : _quoteAmount(profile, cents);
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Row(children: [
            Text(symbol, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (hasPosition) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (quantity > 0 ? green : red).withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (quantity > 0 ? green : red)
                      .withAlpha(100)),
                ),
                child: Text(quantity > 0 ? '多头' : '空头',
                    style: TextStyle(color: quantity > 0 ? green : red,
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ])),
          Text(_quotePrice(profile, mark),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 5),
        Text('净仓 $quantity ${instrument.orderUnit} · '
            '可平 ${position?.availableToClose ?? 0} ${instrument.orderUnit}'),
        if (hasPosition && (position?.availableToClose ?? 0) > 0) ...[
          const SizedBox(height: 7),
          Wrap(spacing: 5, runSpacing: 4, children: [
            const Text('快速减仓', style: TextStyle(
                fontSize: 11, color: Colors.white70)),
            for (final percent in const [25, 50, 100])
              ActionChip(
                label: Text('$percent%'),
                visualDensity: VisualDensity.compact,
                onPressed: _ready && !_busy && state.sessionStatus.isOpen
                    ? () => _prepareIndependentReduceOnly(
                        state, symbol, percent)
                    : null,
              ),
            ActionChip(
              avatar: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('设置保护单'),
              visualDensity: VisualDensity.compact,
              onPressed: _ready && !_busy
                  ? () => _showIndependentConditionalDialog(state, symbol)
                  : null,
            ),
          ]),
          const Text('快速减仓只填充交易页，不会绕过盘口试算、确认或 CAS 写入。',
              style: TextStyle(fontSize: 10, color: Colors.white54)),
        ],
        if (hasPosition) ...[
          const SizedBox(height: 9),
          Wrap(children: [
            _metric('平均成本', _quotePrice(profile, position!.averageEntryCents)),
            _metric('持仓名义', _quoteAmount(profile, notional)),
            _metric('浮动盈亏', signedQuote(unrealized)),
          ]),
          Text('收益率 ${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(2)}%'
              ' · 已实现 ${signedQuote(position.realizedPnlCents)}',
              style: TextStyle(color: unrealized >= 0 ? green : red,
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (usesMargin) ...[
            Row(children: [
              const Expanded(child: Text('风险占用',
                  style: TextStyle(fontSize: 11, color: Colors.white70))),
              Text(risk.marginMode == TxMarginMode.isolated
                  ? '逐仓回报 ${marginRoi >= 0 ? '+' : ''}${marginRoi.toStringAsFixed(2)}%'
                  : '全仓共享权益',
                  style: TextStyle(color: riskColor, fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
            LinearProgressIndicator(
              value: risk.marginMode == TxMarginMode.isolated &&
                      maintenance > 0 && marginBalance != null
                  ? (marginBalance / maintenance / 4).clamp(0.0, 1.0).toDouble()
                  : risk.marginRatio == null
                      ? 0.0
                      : (risk.marginRatio! / 4).clamp(0.0, 1.0).toDouble(),
              minHeight: 5,
              backgroundColor: TxTerminalColors.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(riskColor),
            ),
            const SizedBox(height: 7),
            Wrap(spacing: 10, runSpacing: 5, children: [
              Text('模式 ${risk.marginMode.label}',
                  style: const TextStyle(fontSize: 11)),
              Text(risk.marginMode == TxMarginMode.isolated
                  ? '已分配 ${_quoteAmount(profile, position!.isolatedMarginCents)}'
                  : '占用 ${_quoteAmount(profile, marginBase)}',
                  style: const TextStyle(fontSize: 11)),
              Text('维持 ${_quoteAmount(profile, maintenance)}',
                  style: const TextStyle(fontSize: 11)),
            ]),
            Wrap(spacing: 10, runSpacing: 5, children: [
              if (breakeven != null)
                Text('盈亏平衡 ${_quotePrice(profile, breakeven)}',
                    style: const TextStyle(fontSize: 11,
                        color: TxTerminalColors.gold)),
              if (liquidation != null)
                Text('强平 ${_quotePrice(profile, liquidation)}',
                    style: TextStyle(fontSize: 11, color: riskColor,
                        fontWeight: FontWeight.w700)),
              if (positionBuffer != null)
                Text('安全边际 ${signedQuote(positionBuffer)}',
                    style: TextStyle(fontSize: 11, color: riskColor)),
            ]),
            if (conditionalOrders.isNotEmpty)
              Text('保护单 ${conditionalOrders.length} 笔 · '
                  '${conditionalOrders.map((order) => '${order.kind.label} '
                      '${order.triggerOperator}${_quotePrice(profile, order.triggerPriceCents)}')
                      .join(' · ')}',
                  style: const TextStyle(fontSize: 10,
                      color: TxTerminalColors.cyan)),
            if (liquidation != null)
              Text(risk.marginMode == TxMarginMode.isolated
                  ? '该强平位只对应本仓逐仓保证金，不会直接占用其他持仓。'
                  : '该强平位按全仓账户权益估算，其他持仓盈亏会共同影响它。',
                  style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ] else ...[
            const SizedBox(height: 5),
            const Text('现金现货 · 不使用保证金、融资或强平位。',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('当前无持仓 · 选择全仓或逐仓后，下一笔开仓会按该模式分配风险',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        Align(alignment: Alignment.centerRight,
          child: TextButton(onPressed: () {
            final index = profile.instruments.indexWhere(
                (item) => item.symbol == symbol);
            if (index < 0) return;
            setState(() {
              _symbol = index;
              _page = 1;
              _price.text = (mark / 100).toStringAsFixed(2);
            });
          }, child: const Text('交易此标的 →'))),
      ]),
    ));
  }

  Widget _settings(TxStoredSession saved) {
    final footprint = _storageFootprint;
    final measuredSpeed = _committedSpeed.sampleCount < 2
        ? '等待样本'
        : '${_committedSpeed.achievedMultiplier.toStringAsFixed(1)}×';
    final storageSummary = footprint == null
        ? null
        : 'SQLite ${footprint.databaseMiB.toStringAsFixed(2)} MiB · '
            '${footprint.snapshotCount} 份快照 · 最近 '
            '${footprint.latestSnapshotKiB.toStringAsFixed(1)} KiB';
    return TxSettingsPage(
      appVersion: appVersion,
      rustStatus: _rustStatus,
      ready: _ready,
      running: _auto,
      speed: _speed,
      actualMultiplier: measuredSpeed,
      pulseSeconds: _flow.pulseSeconds,
      automaticSaveMinutes: _automaticSaveMinutes,
      automaticSaveDraft: _automaticSaveDraft,
      checkpointInterval: _checkpointInterval,
      checkpointDraft: _checkpointDraft,
      currentRevision: saved.revision,
      pendingSave: saved.pending,
      pendingOperations: saved.pendingOperations,
      pendingGameMinutes: _trader!.pendingGameMinutes,
      storageSummary: storageSummary,
      onToggle: (_auto || _ready) ? _toggle : null,
      onManualTick: _ready ? () => _tick() : null,
      onCustomSpeed: _ready ? _showCustomSpeed : null,
      onSpeedPreset: _ready ? _changeSpeed : null,
      onSpeedDelta: _ready ? (delta) => _changeSpeed(_speed + delta) : null,
      onPulsePreset: _ready && !_flow.awaitingCommit
          ? _changeMarketPulseSeconds : null,
      onCustomPulse: _ready && !_flow.awaitingCommit
          ? _showCustomMarketPulse : null,
      onAutomaticSaveDraftChanged: _ready
          ? (value) => setState(() => _automaticSaveDraft = value) : null,
      onSaveAutomaticSave: _ready &&
              _automaticSaveDraft != _automaticSaveMinutes
          ? _saveAutomaticSaveMinutes : null,
      onCheckpointDraftChanged: _ready
          ? (value) => setState(() => _checkpointDraft = value) : null,
      onSaveCheckpoint: _ready && _checkpointDraft != _checkpointInterval
          ? _saveCheckpointInterval : null,
      onInspectStorage: _ready ? _inspectStorage : null,
    );
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
            _pageHeader(
              icon: Icons.receipt_long_rounded,
              eyebrow: 'TAPE & REVIEW',
              title: '市场真实逐笔',
              subtitle: '逐笔成交只展示已发生的撮合；订单、成交和复盘分开浏览。',
              status: '最近 $shown / $total 笔',
              accent: TxTerminalColors.cyan,
            ),
            _marketContextBar(session),
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
    if (_independentMode) return _independentRecords();
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
      _pageHeader(
        icon: Icons.receipt_long_rounded,
        eyebrow: 'TAPE & REVIEW',
        title: '真实成交与交易复盘',
        subtitle: '把我的委托、我的成交、市场逐笔和成本复盘分成四个独立视图。',
        status: '只读账本 · 最近 100 条',
        accent: TxTerminalColors.cyan,
      ),
      _marketContextBar(session),
      _title('记录分类', sub: '委托与逐笔展示最近 100 条；复盘汇总全部已提交成交'),
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

  Widget _independentRecords() {
    final state = _independentState;
    if (_independentLoading || state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final profile = state.profile;
    final fills = state.runtime.venue.fills.reversed.where((fill) {
      final buy = state.runtime.venue.order(fill.buyOrderId).ownerId;
      final sell = state.runtime.venue.order(fill.sellOrderId).ownerId;
      return buy == TxIndependentMarketState.playerId ||
          sell == TxIndependentMarketState.playerId;
    }).take(100).toList();
    final orders = state.runtime.venue.orders.reversed.where(
        (order) => order.ownerId == TxIndependentMarketState.playerId)
        .take(100).toList();
    final conditionalOrders = state.runtime.conditionalOrders;
    return ListView(padding: const EdgeInsets.all(14), children: [
      _pageHeader(
        icon: Icons.receipt_long_rounded,
        eyebrow: 'TAPE & REVIEW',
        title: '真实成交与订单',
        subtitle: '${profile.label} · 订单、成交与 CAS 版本分开核对，不混入其他市场。',
        status: '独立账本 · 最近 100 条',
        accent: TxTerminalColors.gold,
      ),
      _marketContextBar(_trader!.current.session),
      _title('记录分类', sub: '未成交委托可撤单；成交记录只来自本板块订单簿'),
      Card(child: ListTile(
        title: Text('市场成交 ${state.runtime.venue.fillCount} 笔 · '
            '我的成交 ${fills.length} 笔'),
        subtitle: Text('个人委托 ${orders.length} 笔 · CAS r${state.sequence}'),
      )),
      if (conditionalOrders.isNotEmpty) ...[
        const Text('待触发保护单', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final condition in conditionalOrders)
          Card(child: ListTile(
            dense: true,
            title: Text('${condition.kind.label} · ${condition.symbol} · '
                '${condition.side == TxSide.sell ? '卖出' : '买入'}'),
            subtitle: Text('${condition.triggerOperator} '
                '${_quotePrice(profile, condition.triggerPriceCents)} · '
                '数量 ${condition.quantity} · 当前标记 '
                '${_quotePrice(profile, state.markPriceCents(condition.symbol))}'),
            trailing: IconButton(
              tooltip: '取消保护单',
              icon: const Icon(Icons.delete_outline),
              onPressed: _ready && !_busy
                  ? () => _cancelIndependentConditional(condition.id)
                  : null,
            ),
          )),
      ],
      if (orders.isNotEmpty) ...[
        const Text('最近委托', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final order in orders) Card(child: ListTile(
          dense: true,
          title: Text('${order.symbol} · ${order.side == TxSide.buy ? '买' : '卖'} '
              '成交${order.filled}/${order.quantity}'),
          subtitle: Text('${order.id} · ${order.timeInForce.label} · '
              '${order.status.name}${order.reduceOnly ? ' · 只减仓' : ''}'
              '${order.id.startsWith('TRIGGER') ? ' · 保护单触发' : ''}'
              '${order.rejectReason == null ? '' :
                ' · ${order.rejectReason}'}'),
          trailing: order.remaining > 0 &&
                  (order.status == TxStatus.open ||
                      order.status == TxStatus.partiallyFilled)
              ? IconButton(icon: const Icon(Icons.close),
                  onPressed: _ready ? () => _cancelIndependent(order.id) : null)
              : null,
        )),
      ],
      if (fills.isEmpty)
        const ListTile(title: Text('当前独立账户暂无成交')),
      for (final fill in fills)
        Card(child: ListTile(
          dense: true,
          title: Text('${fill.symbol} · ${fill.quantity} · '
              '${_quotePrice(profile, fill.priceCents)}'),
          subtitle: Text('第 ${fill.gameDay} 天 '
              '${fill.minuteOfDay ~/ 60}:${(fill.minuteOfDay % 60).toString().padLeft(2, '0')} · '
              '${fill.id}'),
          trailing: Text(fill.buyOrderId.startsWith('PLAYER') ? '买入' : '卖出'),
        )),
    ]);
  }

  /// Android system Back: return to the market tab, then request explicit
  /// confirmation before exiting. If an atomic trade is in flight, refusing
  /// the exit preserves the single-writer transaction boundary.
  Future<void> _onSystemBack() async {
    if (!mounted || _loading) return;
    if (_page != 0) {
      setState(() => _page = 0);
      return;
    }
    if (_auto) _pause();
    if (_busy || (_trader != null && _trader!.blocked)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('交易正在提交或存储异常，请等待完成后再退出'),
      ));
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('退出 Terminal X？'),
        content: const Text('游戏已暂停。确认退出应用吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续游戏')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出游戏')),
        ],
      ),
    );
    if (leave == true && mounted && !_busy) {
      final trader = _trader;
      if (trader != null && trader.hasPendingPersistence) {
        try {
          final saved = await trader.flushPending();
          if (mounted) {
            setState(() => _notice = '退出前已安全保存 SQLite r${saved.revision}');
          }
        } catch (error) {
          if (mounted) {
            setState(() => _fault = '退出前保存失败，应用未退出：$error');
          }
          return;
        }
      }
      await SystemNavigator.pop();
    }
  }

  Future<void> _closeTrader() async {
    final trader = _trader;
    if (trader == null) return;
    _cancelIndependentPrewarm = true;
    try {
      await _independentMarkets?.waitForIdle();
    } catch (_) {
      // The independent adapter is fail-closed; the primary SQLite close
      // still runs so an already committed A-share state is not stranded.
    }
    final warmup = _candleWarmup;
    if (warmup != null) {
      try {
        await warmup;
      } catch (_) {
        // _warmCandleHistory publishes the warning itself; shutdown still
        // proceeds against the verified account.
      }
    }
    try {
      await trader.waitForRecovery();
    } catch (_) {
      // The service has already completed its fail-closed recovery attempt;
      // shutdown still proceeds without fabricating a successful save.
    }
    try {
      await _closeService(trader);
    } catch (_) {
      // The widget is already being torn down; a failed flush is still
      // fail-closed in TxTradingService and is not replaced with a fake save.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackTicker.dispose();
    _startupTimer?.cancel();
    _startupStopwatch.stop();
    _seconds.dispose();
    _chartSeconds.dispose();
    _marketRepaint.dispose();
    _settling.dispose();
    _pulseSettling.dispose();
    _settlementPhase.dispose();
    _qty.dispose();
    _price.dispose();
    final work = _operation;
    if (work == null) {
      unawaited(_closeTrader());
    } else {
      work.whenComplete(() => _closeTrader());
    }
    super.dispose();
  }

  List<Widget> _topBarActions(TxSession session) => [
    PopupMenuButton<TxMarketMode>(
      tooltip: '切换市场',
      icon: const Icon(Icons.public_outlined),
      onSelected: (mode) => unawaited(_selectMarketMode(mode, session)),
      itemBuilder: (context) => [
        for (final profile in TxMarketProfile.values)
          PopupMenuItem<TxMarketMode>(
            value: profile.mode,
            enabled: profile.mode != _marketMode ||
                (profile.mode != TxMarketMode.aShare &&
                    _independentState == null),
            child: Row(children: [
              SizedBox(width: 22, child: Icon(
                  profile.mode == _marketMode
                      ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: profile.mode == _marketMode
                      ? TxTerminalColors.cyan
                      : TxTerminalColors.secondaryText)),
              Expanded(child: Text('${profile.label} · '
                  '${_statusForMode(session, profile.mode).label}')),
            ]),
          ),
      ],
    ),
    PopupMenuButton<int>(
      tooltip: '运行倍率 $_speed×',
      icon: const Icon(Icons.speed_outlined),
      onSelected: (value) => value < 0
          ? unawaited(_showCustomSpeed())
          : _changeSpeed(value),
      itemBuilder: (context) => [
        for (final value in const [1, 5, 10, 30, 60, 120, 300, 600, 1200])
          PopupMenuItem<int>(
            value: value,
            enabled: _ready && !_flow.awaitingCommit && !_flow.faulted,
            child: Text('${value}×${value == _speed ? '  ✓' : ''}'),
          ),
        PopupMenuItem<int>(
          value: -1,
          enabled: _ready && !_flow.awaitingCommit && !_flow.faulted,
          child: const Text('自定义倍率…'),
        ),
      ],
    ),
    PopupMenuButton<String>(
      tooltip: '常用操作',
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) {
        if (value == 'tick') _tick();
        if (value == 'fast') {
          if (_marketMode == TxMarketMode.aShare) {
            _fastForwardClosed();
          } else {
            _fastForwardIndependentClosed();
          }
        }
        if (value == 'settings') setState(() => _page = 4);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'tick',
          enabled: _ready,
          child: const Text('推进 1 游戏分钟'),
        ),
        if (!_selectedSessionStatus(session).isOpen)
          const PopupMenuItem<String>(
              value: 'fast', child: Text('快进到下次开盘前')),
        const PopupMenuItem<String>(value: 'settings', child: Text('打开设置')),
      ],
    ),
    IconButton(
      tooltip: _auto ? '暂停' : '运行',
      onPressed: (_auto || _ready) ? _toggle : null,
      icon: Icon(_auto ? Icons.pause_circle : Icons.play_circle_outline),
    ),
  ];

  @override
  Widget build(BuildContext context) => TxBackExitGuard(
    onBack: _onSystemBack,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    if (_loading) return Scaffold(body: SafeArea(child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 330),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('TERMINAL X', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 26, letterSpacing: 4)),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(_startupStage, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _startupProgress, minHeight: 4),
            const SizedBox(height: 8),
            Text('冷启动已用 ${_startupTimeLabel()} · 存档校验完成后先进入界面',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])))));
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
        ]), actions: _topBarActions(session)),
      body: Column(children: [
        TxTerminalStatus(seconds: _seconds, step: session.step,
          revision: stored.revision, running: _auto,
          speed: _speed, busy: _busy, settling: _settling,
          settlementPhase: _settlementPhase,
          settlingPulse: _pulseSettling,
          pendingSave: stored.pending,
          pendingOperations: stored.pendingOperations,
          pendingGameMinutes: _trader!.pendingGameMinutes,
          automaticSaveMinutes: _automaticSaveMinutes),
        if (_historyWarming) Column(children: [
          LinearProgressIndicator(value: _startupProgress, minHeight: 3),
          Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
            child: Row(children: [
              const SizedBox(width: 8, height: 8,
                child: CircularProgressIndicator(strokeWidth: 1.5)),
              const SizedBox(width: 7),
              Expanded(child: Text(
                '${_startupStage} · 已用 ${_startupTimeLabel()}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.amberAccent, fontSize: 11))),
            ])),
        ]),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_fault != null) Padding(padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(_fault!, style: const TextStyle(color: red)),
                if (_trader != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _recoveringStorage ? null : _recoverStorage,
                    icon: _recoveringStorage
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.verified_outlined, size: 17),
                    label: Text(_recoveringStorage
                        ? '正在重新校验…' : '重新校验 SQLite 并恢复'),
                  ),
                ],
              ])),
        if (_fault == null) Padding(padding: const EdgeInsets.all(8),
          child: Text(_notice, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12))),
        Expanded(child: switch (_page) {
          0 => _market(session),
          1 => _trading(session),
          2 => _assets(session, stored),
          3 => _records(session),
          _ => _settings(stored),
        }),
      ]),
      // The system keyboard takes priority over bottom navigation.
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
        ? null : NavigationBar(selectedIndex: _page,
        onDestinationSelected: (i) => setState(() => _page=i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: '行情'),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: '交易'),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '资产'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '记录'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置'),
        ]),
    );
  }
}
