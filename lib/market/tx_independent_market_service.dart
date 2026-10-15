import 'dart:async';
import 'dart:math' as math;

import '../engine/tx_engine.dart';
import '../storage/tx_sqlite_store.dart';
import 'tx_candle_history.dart';
import 'tx_market_conditional_orders.dart';
import 'tx_market_profiles.dart';
import 'tx_market_risk_core.dart';
import 'tx_market_runtime.dart';
import 'tx_market_session_schedule.dart';
import 'tx_market_venue.dart';

/// The executable account boundary for a non-A-share market.
///
/// The A-share account remains owned by [TxTradingService]/Rust. Other modes
/// use their own venue, risk core and SQLite CAS sequence, so changing market
/// mode can never reinterpret CNY shares as USD, contracts or coins. This is
/// intentionally a local deterministic feed: every quote and print comes
/// from the venue's visible book and participant orders.
class TxIndependentMarketState {
  TxIndependentMarketState._({
    required this.mode,
    required this.runtime,
    required this.sequence,
  }) : profile = TxMarketProfile.of(mode) {
    _rebuildCandles();
  }

  static const playerId = 'PLAYER';
  static const maxCandleCount = 1500;

  final TxMarketMode mode;
  final TxMarketProfile profile;
  TxMarketRuntime runtime;
  int sequence;
  final Map<String, List<TxCandle>> _candles = {};
  // Venue fills are append-only. Keep the cursor so a CAS save can extend the
  // display-only OHLC cache instead of scanning the complete fill journal.
  int _candleFillCursor = 0;

  // Process-local quote telemetry. It is intentionally not persisted with
  // the economic snapshot: after a restart the first open must rebuild the
  // visible ten-level book instead of trusting an old refresh boundary.
  int _quoteRefreshCount = 0;
  int? _lastQuoteRefreshStep;

  TxMarketCore get player => runtime.venue.account(playerId);

  TxMarketRiskSnapshot get playerRisk => player.snapshot();

  int get playerLeverageMultiple => player.leverageMultiple;

  int get quoteRefreshCount => _quoteRefreshCount;

  int? get lastQuoteRefreshStep => _lastQuoteRefreshStep;

  TxMarketVenueSettlement? lastSettlement;

  TxMarketSessionStatus get sessionStatus => profile.schedule.status(
        gameDay: runtime.gameDay,
        minuteOfDay: runtime.minuteOfDay,
      );

  List<TxCandle> candlesFor(String symbol) =>
      List.unmodifiable(_candles[symbol] ?? const <TxCandle>[]);

  int markPriceCents(String symbol) => player.markPriceCents(symbol);

  void _rebuildCandles() {
    _candles.clear();
    for (final instrument in profile.instruments) {
      _candles[instrument.symbol] = <TxCandle>[];
    }
    final fillCount = runtime.venue.fillCount;
    for (var index = 0; index < fillCount; index++) {
      final fill = runtime.venue.fillAt(index);
      // Normal venue history is already in execution order. If an imported
      // legacy snapshot violates that ordering, fall back to the sorted
      // rebuild below rather than presenting a silently misordered chart.
      if (!_appendFill(fill)) {
        _rebuildCandlesSorted([
          for (var i = 0; i < fillCount; i++) runtime.venue.fillAt(i),
        ]);
        _candleFillCursor = fillCount;
        return;
      }
    }
    _candleFillCursor = fillCount;
  }

  void _rebuildCandlesSorted(List<TxMarketVenueFill> fills) {
    _candles.clear();
    for (final instrument in profile.instruments) {
      final byStep = <int, _CandleDraft>{};
      for (final fill in fills.where(
          (item) => item.symbol == instrument.symbol)) {
        final step = (fill.gameDay - 1) * 1440 + fill.minuteOfDay;
        final draft = byStep.putIfAbsent(
            step, () => _CandleDraft(priceCents: fill.priceCents));
        draft.highCents = math.max(draft.highCents, fill.priceCents);
        draft.lowCents = math.min(draft.lowCents, fill.priceCents);
        draft.closeCents = fill.priceCents;
        draft.volume += fill.quantity;
      }
      final steps = byStep.keys.toList()..sort();
      final values = <TxCandle>[
        for (final step in steps)
          TxCandle(
            step: step,
            openCents: byStep[step]!.openCents,
            highCents: byStep[step]!.highCents,
            lowCents: byStep[step]!.lowCents,
            closeCents: byStep[step]!.closeCents,
            volumeShares: byStep[step]!.volume,
          ),
      ];
      _candles[instrument.symbol] = values.length <= maxCandleCount
          ? values
          : values.sublist(values.length - maxCandleCount);
    }
  }

  bool _appendFill(TxMarketVenueFill fill) {
    final values = _candles[fill.symbol];
    if (values == null) return false;
    final step = (fill.gameDay - 1) * 1440 + fill.minuteOfDay;
    if (values.isEmpty) {
      values.add(TxCandle(
        step: step,
        openCents: fill.priceCents,
        highCents: fill.priceCents,
        lowCents: fill.priceCents,
        closeCents: fill.priceCents,
        volumeShares: fill.quantity,
      ));
    } else {
      final previous = values.last;
      if (step == previous.step) {
        values[values.length - 1] = TxCandle(
          step: step,
          openCents: previous.openCents,
          highCents: math.max(previous.highCents, fill.priceCents),
          lowCents: math.min(previous.lowCents, fill.priceCents),
          closeCents: fill.priceCents,
          volumeShares: previous.volumeShares + fill.quantity,
        );
      } else if (step > previous.step) {
        values.add(TxCandle(
          step: step,
          openCents: fill.priceCents,
          highCents: fill.priceCents,
          lowCents: fill.priceCents,
          closeCents: fill.priceCents,
          volumeShares: fill.quantity,
        ));
      } else {
        return false;
      }
    }
    if (values.length > maxCandleCount) {
      values.removeRange(0, values.length - maxCandleCount);
    }
    return true;
  }

  void _updateCandles() {
    final fillCount = runtime.venue.fillCount;
    if (_candleFillCursor > fillCount) {
      _rebuildCandles();
      return;
    }
    for (var index = _candleFillCursor; index < fillCount; index++) {
      if (!_appendFill(runtime.venue.fillAt(index))) {
        _rebuildCandles();
        return;
      }
    }
    _candleFillCursor = fillCount;
  }
}

/// Serialized adapter for all independent market modes.
///
/// Every public mutation is queued. A player order, a quote refresh and a
/// market-clock advance therefore share one SQLite CAS boundary instead of
/// racing one another when the user changes tabs or returns from background.
class TxIndependentMarketService {
  TxIndependentMarketService(this.database);

  static const prewarmCandleCount = 8;
  static const quoteRefreshIntervalMinutes = 5;
  static const _visibleQuoteLevels = 10;
  // Keep a small real queue behind the ten displayed levels so normal FLOW
  // and smart-trader executions do not make the visible book blink sparse
  // between scheduled maker refreshes. The UI still exposes only ten levels.
  static const _quoteReserveLevels = 10;

  final TxSqliteStore database;
  final Map<TxMarketMode, TxIndependentMarketState> _states = {};
  Future<void> _tail = Future<void>.value();
  int _orderSerial = 0;

  TxIndependentMarketState? state(TxMarketMode mode) => _states[mode];

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final previous = _tail;
    late Future<T> result;
    result = previous.then<T>((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<TxIndependentMarketState> open({
    required TxMarketMode mode,
    required int gameDay,
    required int minuteOfDay,
  }) => _enqueue(() => _openUnlocked(
        mode: mode, gameDay: gameDay, minuteOfDay: minuteOfDay,
        prewarmMinutes: prewarmCandleCount));

  /// Keep every opened independent venue on the same deterministic game clock.
  /// Opening one tab must not freeze another board that is already warm: each
  /// venue still applies its own session schedule and therefore only open
  /// boards create quotes, fills and candles. [openMissing] remains available
  /// to deterministic callers that explicitly want all modes materialized;
  /// the Flutter cold-start path uses the lazy form.
  Future<Map<TxMarketMode, TxIndependentMarketState>> syncAll({
    required int gameDay,
    required int minuteOfDay,
    bool openMissing = true,
  }) => _enqueue(() async {
        _validateClock(gameDay, minuteOfDay);
        final states = <TxMarketMode, TxIndependentMarketState>{};
        final modes = openMissing
            ? TxMarketMode.values.where((mode) => mode != TxMarketMode.aShare)
            : _states.keys.where((mode) => mode != TxMarketMode.aShare).toList();
        for (final mode in modes) {
          states[mode] = await _openUnlocked(
              mode: mode, gameDay: gameDay, minuteOfDay: minuteOfDay);
        }
        return states;
      });

  /// Open at most one missing board per queued operation. The UI uses this as
  /// a low-priority prewarm after the first frame, yielding between markets so
  /// a player tap can enter the queue without waiting behind four cold opens.
  /// Once a board exists, normal clock sync continues to advance it; no
  /// historical fills are discarded and no chart is rebuilt for other modes.
  Future<TxMarketMode?> prewarmNext({
    required int gameDay,
    required int minuteOfDay,
  }) => _enqueue(() async {
        _validateClock(gameDay, minuteOfDay);
        for (final mode in TxMarketMode.values) {
          if (mode == TxMarketMode.aShare || _states.containsKey(mode)) {
            continue;
          }
          await _openUnlocked(
              mode: mode, gameDay: gameDay, minuteOfDay: minuteOfDay,
              prewarmMinutes: prewarmCandleCount);
          return mode;
        }
        return null;
      });

  /// Move an already opened market to the visible game clock. The independent
  /// market has its own CAS envelope, so it can keep trading while the A-share
  /// automatic candidate is waiting for its separate SQLite flush.
  Future<TxIndependentMarketState> sync({
    required TxMarketMode mode,
    required int gameDay,
    required int minuteOfDay,
  }) => _enqueue(() async {
        final current = _requireState(mode);
        await _syncUnlocked(current, gameDay, minuteOfDay);
        return current;
      });

  /// Skip only the empty part of the selected closed session. The runtime is
  /// left at the last closed minute before the next opening boundary; the
  /// following normal minute sync is still responsible for real quotes and
  /// prints. Player GTC orders remain, while market-maker orders are withdrawn.
  Future<TxIndependentMarketState> fastForwardClosed({
    required TxMarketMode mode,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        if (state.sessionStatus.isOpen) return state;
        final initial = (state.runtime.gameDay - 1) * 1440 +
            state.runtime.minuteOfDay;
        var nextOpen = initial + 1;
        const maxSearchMinutes = 10080;
        while (true) {
          final day = nextOpen ~/ 1440 + 1;
          final minute = nextOpen % 1440;
          if (state.profile.schedule.status(
              gameDay: day, minuteOfDay: minute).isOpen) break;
          nextOpen++;
          if (nextOpen - initial > maxSearchMinutes) {
            throw StateError('No next market opening found within one game week');
          }
        }
        final target = nextOpen - 1;
        if (target <= initial) return state;
        await _syncUnlocked(
          state,
          target ~/ 1440 + 1,
          target % 1440,
        );
        return state;
      });

  Future<TxMarketVenueOrder> place({
    required TxMarketMode mode,
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    required int? limitPriceCents,
    required TxTimeInForce timeInForce,
    required int gameDay,
    required int minuteOfDay,
    bool reduceOnly = false,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        if (state.runtime.gameDay != gameDay ||
            state.runtime.minuteOfDay != minuteOfDay) {
          throw StateError('Independent market clock changed before order; '
              'refresh the board and retry');
        }
        final order = state.runtime.place(
          id: _nextOrderId(state, 'PLAYER'),
          ownerId: TxIndependentMarketState.playerId,
          symbol: symbol,
          side: side,
          kind: kind,
          quantity: quantity,
          limitPriceCents: limitPriceCents,
          timeInForce: timeInForce,
          reduceOnly: reduceOnly,
        );
        await _save(state);
        return order;
      });

  /// Store a stop-loss or take-profit instruction against the player's
  /// currently closable net position. The instruction is durable, but it is
  /// not a resting venue order: the next verified open-market mark decides
  /// whether it becomes a real reduce-only market order.
  Future<TxMarketConditionalOrder> placeConditional({
    required TxMarketMode mode,
    required String symbol,
    required TxMarketConditionalOrderKind kind,
    required int triggerPriceCents,
    required int quantity,
    required int gameDay,
    required int minuteOfDay,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        if (state.runtime.gameDay != gameDay ||
            state.runtime.minuteOfDay != minuteOfDay) {
          throw StateError('Independent market clock changed before protection '
              'order; refresh the board and retry');
        }
        final instrument = state.profile.instruments.firstWhere(
          (item) => item.symbol == symbol,
          orElse: () => throw ArgumentError.value(symbol, 'symbol'),
        );
        final rule = TxMarketRiskRules.forMode(mode);
        rule.validatePrice(triggerPriceCents);
        rule.validateQuantity(quantity);
        final position = state.player.position(symbol);
        if (position.isFlat || position.availableToClose < quantity) {
          throw StateError('保护单必须对应当前可平仓位，最多可设置 '
              '${position.availableToClose} ${instrument.orderUnit}');
        }
        final order = TxMarketConditionalOrder(
          id: _nextOrderId(state, 'COND'),
          symbol: symbol,
          side: position.netQuantity > 0 ? TxSide.sell : TxSide.buy,
          kind: kind,
          triggerPriceCents: triggerPriceCents,
          quantity: quantity,
          createdGameDay: gameDay,
          createdMinuteOfDay: minuteOfDay,
        );
        state.runtime.conditionalOrders.add(order);
        await _save(state);
        return order;
      });

  /// Cancel a still-pending protection instruction. Triggered instructions
  /// are removed atomically before their reduce-only order is submitted, so
  /// this endpoint never cancels a fill that has already entered the venue.
  Future<TxMarketConditionalOrder> cancelConditional({
    required TxMarketMode mode,
    required String orderId,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        final index = state.runtime.conditionalOrders.indexWhere(
          (order) => order.id == orderId,
        );
        if (index < 0) {
          throw StateError('保护单不存在或已触发：$orderId');
        }
        final order = state.runtime.conditionalOrders.removeAt(index);
        await _save(state);
        return order;
      });

  /// Change only the player's margin regime. The core rejects changes while
  /// exposed; active player orders are also blocked so a pending order cannot
  /// be executed under a different leverage after the UI selection.
  Future<int> setPlayerLeverage({
    required TxMarketMode mode,
    required int multiple,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        final active = state.runtime.venue.activeOrders.where(
            (order) => order.ownerId == TxIndependentMarketState.playerId);
        if (active.isNotEmpty) {
          throw StateError('请先撤销未成交委托，再调整杠杆');
        }
        state.player.setLeverageMultiple(multiple);
        await _save(state);
        return state.player.leverageMultiple;
      });

  /// Change only the player's collateral scope. Existing positions and
  /// resting orders are blocked so a live order cannot be reinterpreted under
  /// a different liquidation model between preflight and execution.
  Future<TxMarginMode> setPlayerMarginMode({
    required TxMarketMode mode,
    required TxMarginMode marginMode,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        final active = state.runtime.venue.activeOrders.where(
            (order) => order.ownerId == TxIndependentMarketState.playerId);
        if (active.isNotEmpty) {
          throw StateError('请先撤销未成交委托，再调整保证金模式');
        }
        state.player.setMarginMode(marginMode);
        await _save(state);
        return state.player.marginMode;
      });

  Future<TxMarketVenueOrder> cancel({
    required TxMarketMode mode,
    required String orderId,
  }) => _enqueue(() async {
        final state = _requireState(mode);
        final order = state.runtime.cancel(orderId,
            ownerId: TxIndependentMarketState.playerId);
        await _save(state);
        return order;
      });

  TxMarketExecutionPreview preview({
    required TxMarketMode mode,
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    required int? limitPriceCents,
    required TxTimeInForce timeInForce,
    required int gameDay,
    required int minuteOfDay,
    bool reduceOnly = false,
  }) {
    final state = _requireState(mode);
    if (state.runtime.gameDay != gameDay ||
        state.runtime.minuteOfDay != minuteOfDay) {
      throw StateError('Independent market clock changed before preview; '
          'refresh the board and retry');
    }
    return state.runtime.venue.previewOrder(
      ownerId: TxIndependentMarketState.playerId,
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
      timeInForce: timeInForce,
      gameDay: gameDay,
      minuteOfDay: minuteOfDay,
      reduceOnly: reduceOnly,
    );
  }

  /// Discard only in-memory views after a primary SQLite recovery. The next
  /// market selection re-reads and re-verifies every independent envelope.
  void clearInMemoryStates() => _states.clear();

  Future<void> waitForIdle() => _tail;

  Future<TxIndependentMarketState> _openUnlocked({
    required TxMarketMode mode,
    required int gameDay,
    required int minuteOfDay,
    int prewarmMinutes = 0,
  }) async {
    _validateMode(mode);
    final existing = _states[mode];
    if (existing != null) {
      await _syncUnlocked(existing, gameDay, minuteOfDay);
      return existing;
    }

    final stored = await database.readMarketRuntime(mode);
    late final TxIndependentMarketState next;
    if (stored == null) {
      final targetStep = (gameDay - 1) * 1440 + minuteOfDay;
      final warmupSteps = prewarmMinutes < 1
          ? 0
          : math.min(prewarmMinutes - 1, targetStep);
      final startStep = targetStep - warmupSteps;
      next = TxIndependentMarketState._(
        mode: mode,
        runtime: _freshRuntime(
          mode,
          startStep ~/ 1440 + 1,
          startStep % 1440,
        ),
        sequence: 0,
      );
      _states[mode] = next;
      try {
        if (warmupSteps == 0) {
          await _syncUnlocked(next, gameDay, minuteOfDay,
              force: true, persist: false);
        } else {
          // Build a fixed-size first-look window in memory. Only the final
          // runtime is written, so initial history is useful without doing a
          // SQLite CAS and full JSON envelope for every warmup minute.
          await _syncUnlocked(
            next,
            startStep ~/ 1440 + 1,
            startStep % 1440,
            force: true,
            persist: false,
          );
          for (var step = startStep + 1;
              step <= targetStep;
              step++) {
            await _syncUnlocked(
              next,
              step ~/ 1440 + 1,
              step % 1440,
              persist: false,
            );
          }
        }
        // Prewarm flow intentionally consumes real quotes to build the first
        // look-back window. Rebuild the inside book once at the visible target
        // minute so the first player preview starts from a fresh, finite BBO
        // without replaying another minute of FLOW or smart traders.
        if (next.sessionStatus.isOpen) {
          _refreshQuotes(next, gameDay, minuteOfDay);
          next._lastQuoteRefreshStep = targetStep;
          next._quoteRefreshCount++;
        }
        await _save(next);
      } catch (_) {
        _states.remove(mode);
        rethrow;
      }
    } else {
      next = TxIndependentMarketState._(
        mode: mode,
        runtime: stored.runtime,
        sequence: stored.sequence,
      );
      _states[mode] = next;
      await _syncUnlocked(next, gameDay, minuteOfDay);
    }
    return next;
  }

  Future<void> _syncUnlocked(TxIndependentMarketState state, int gameDay,
      int minuteOfDay, {bool force = false, bool persist = true}) async {
    _validateClock(gameDay, minuteOfDay);
    final runtime = state.runtime;
    final moved = gameDay > runtime.gameDay ||
        (gameDay == runtime.gameDay && minuteOfDay > runtime.minuteOfDay);
    final beforeRuntime = gameDay < runtime.gameDay ||
        (gameDay == runtime.gameDay && minuteOfDay < runtime.minuteOfDay);
    final status = state.profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    final participantsAdded = _ensureParticipantAccounts(state);
    if (beforeRuntime) {
      // A stale UI reopen may carry an older clock. Account migration is still
      // safe to persist, but never replay that historical minute's quotes or
      // participant orders just because the visible book needs more levels.
      if (participantsAdded && persist) await _save(state);
      return;
    }
    final currentStep = (gameDay - 1) * 1440 + minuteOfDay;
    final quoteRefreshDue = status.isOpen &&
        (state._lastQuoteRefreshStep == null ||
            currentStep < state._lastQuoteRefreshStep! ||
            currentStep - state._lastQuoteRefreshStep! >=
                quoteRefreshIntervalMinutes);
    if (!moved && !force && !participantsAdded && !quoteRefreshDue) return;
    // A scheduled quote repair at the same clock position must not replay
    // FLOW or smart traders. Only a real minute advance (or the explicit
    // first warmup force) may create that minute's prints. Temporary depth
    // thinning is allowed between scheduled refreshes so normal fills do not
    // cause a cancel/repost storm every frame.
    final shouldEmitMinute = moved || force;
    if (moved) {
      final transition = runtime.advanceClock(
          nextGameDay: gameDay, nextMinuteOfDay: minuteOfDay);
      state.lastSettlement = transition.settlement;
    }
    if (status.isOpen) {
      for (var index = 0; index < state.profile.instruments.length; index++) {
        final instrument = state.profile.instruments[index];
        final price = _markFor(
            state.mode, index, instrument.symbol, gameDay, minuteOfDay,
            runtime.venue.account(TxIndependentMarketState.playerId));
        // The enclosing CAS save audits the complete venue once. Avoid an
        // O(history) invariant pass for every symbol in the same minute.
        runtime.markToMarket(
            symbol: instrument.symbol, priceCents: price,
            validateAfter: false);
      }
      if (quoteRefreshDue) {
        _refreshQuotes(state, gameDay, minuteOfDay);
        state._lastQuoteRefreshStep = currentStep;
        state._quoteRefreshCount++;
      }
      if (shouldEmitMinute) {
        _evaluateConditionalOrders(state);
      }
      if (shouldEmitMinute) {
        _emitSyntheticFlow(state, gameDay, minuteOfDay);
        _emitSmartTraderFlow(state, gameDay, minuteOfDay);
      }
    } else {
      _cancelMarketMakerOrders(state);
      // A closed session withdraws displayed liquidity. Force a fresh quote
      // cycle at the next open rather than carrying a stale cadence boundary
      // across the break.
      state._lastQuoteRefreshStep = null;
    }
    if (persist) await _save(state);
  }

  /// Evaluate protection instructions only after the current minute's mark
  /// has been accepted by every account. A triggered instruction is consumed
  /// once, then its reduce-only market order follows the same finite book and
  /// risk gates as a player ticket; a rejected remainder remains visible in
  /// venue order history instead of being retried invisibly.
  void _evaluateConditionalOrders(TxIndependentMarketState state) {
    if (state.runtime.conditionalOrders.isEmpty) return;
    final pending = List<TxMarketConditionalOrder>.from(
        state.runtime.conditionalOrders);
    for (final condition in pending) {
      final mark = state.player.markPriceCents(condition.symbol);
      if (!condition.shouldTrigger(mark)) continue;

      state.runtime.conditionalOrders.removeWhere(
          (order) => order.id == condition.id);
      final position = state.player.position(condition.symbol);
      final available = position.availableToClose;
      if (available < 1) continue;
      final quantity = math.min(condition.quantity, available);
      try {
        state.runtime.place(
          id: _nextOrderId(state, 'TRIGGER'),
          ownerId: TxIndependentMarketState.playerId,
          symbol: condition.symbol,
          side: condition.side,
          kind: TxKind.market,
          quantity: quantity,
          limitPriceCents: null,
          timeInForce: TxTimeInForce.gtc,
          reduceOnly: true,
          validateAfter: false,
        );
      } on StateError {
        // The venue keeps deterministic risk/conflict failures explicit. A
        // single stale protection instruction must not block other markets.
      } on ArgumentError {
        // The position may have changed between snapshots; consume the
        // instruction rather than creating an unbounded retry loop.
      }
    }
  }

  Future<void> _save(TxIndependentMarketState state) async {
    final saved = await database.saveMarketRuntime(state.runtime,
        expectedSequence: state.sequence);
    state.sequence = saved.sequence;
    state.runtime = saved.runtime;
    state._updateCandles();
  }

  void _refreshQuotes(TxIndependentMarketState state, int gameDay,
      int minuteOfDay) {
    _cancelMarketMakerOrders(state);
    final rule = TxMarketRiskRules.forMode(state.mode);
    for (var index = 0; index < state.profile.instruments.length; index++) {
      final instrument = state.profile.instruments[index];
      final mark = state.player.markPriceCents(instrument.symbol);
      // The old fixed 10bp half-spread made a one-unit taker order look like
      // a price shock even when it consumed only the best level. Keep a
      // market-specific, finite spread while aligning it to the instrument
      // tick size.
      final spreadBps = _quoteSpreadBps(state.mode);
      final spread = math.max(
          rule.tickSizeCents * 2,
          (mark * spreadBps + 9999) ~/ 10000);
      final quantity = _makerQuoteBaseQuantity(state.mode);
      for (var level = 0;
          level < _visibleQuoteLevels + _quoteReserveLevels;
          level++) {
        final distance = spread * (level + 1);
        final bid = math.max(rule.tickSizeCents, mark - distance);
        final ask = mark + distance;
        // Both funded liquidity providers quote both sides. The first maker
        // owns the inside level, so the autonomous buy+sell pair can recycle
        // inventory through a real spread without exhausting one finite LP.
        state.runtime.place(
          id: _nextOrderId(state, 'MM-A-BID'),
          ownerId: 'MM-A',
          symbol: instrument.symbol,
          side: TxSide.buy,
          kind: TxKind.limit,
          quantity: quantity + (level % 4),
          limitPriceCents: bid,
          timeInForce: TxTimeInForce.gtc,
          validateAfter: false,
        );
        state.runtime.place(
          id: _nextOrderId(state, 'MM-B-BID'),
          ownerId: 'MM-B',
          symbol: instrument.symbol,
          side: TxSide.buy,
          kind: TxKind.limit,
          quantity: quantity + (level % 4),
          limitPriceCents: bid,
          timeInForce: TxTimeInForce.gtc,
          validateAfter: false,
        );
        state.runtime.place(
          id: _nextOrderId(state, 'MM-A-ASK'),
          ownerId: 'MM-A',
          symbol: instrument.symbol,
          side: TxSide.sell,
          kind: TxKind.limit,
          quantity: quantity + (level % 4),
          limitPriceCents: ask,
          timeInForce: TxTimeInForce.gtc,
          validateAfter: false,
        );
        state.runtime.place(
          id: _nextOrderId(state, 'MM-B-ASK'),
          ownerId: 'MM-B',
          symbol: instrument.symbol,
          side: TxSide.sell,
          kind: TxKind.limit,
          quantity: quantity + (level % 4),
          limitPriceCents: ask,
          timeInForce: TxTimeInForce.gtc,
          validateAfter: false,
        );
      }
    }
  }

  void _emitSyntheticFlow(TxIndependentMarketState state, int gameDay,
      int minuteOfDay) {
    final timeKey = (gameDay - 1) * 1440 + minuteOfDay;
    final baseQuantity = _flowOrderQuantity(state.mode);
    final pressureStep = _flowPressureStep(state.mode);
    // Every open minute gets an auditable print for every instrument. A
    // perfectly balanced one-lot buy/sell pair used to remain at the same
    // inside quote forever, so the independent candles were mostly flat gray
    // wicks even though the book technically had ten levels. The deterministic
    // pressure is deliberately modest and alternates over time: it lets a
    // real participant sweep finite levels, while its opposite leg keeps FLOW
    // from becoming an unbounded hidden price source.
    for (var index = 0; index < state.profile.instruments.length; index++) {
      final instrument = state.profile.instruments[index];
      final wave = ((timeKey * 5 + index * 17) % 7) - 3;
      final buyQuantity = baseQuantity +
          math.max(0, wave).toInt() * pressureStep;
      final sellQuantity = baseQuantity +
          math.max(0, -wave).toInt() * pressureStep;
      final buy = (int quantity) => state.runtime.place(
        id: _nextOrderId(state, 'FLOW-BUY'),
        ownerId: 'FLOW',
        symbol: instrument.symbol,
        side: TxSide.buy,
        kind: TxKind.market,
        quantity: quantity,
        limitPriceCents: null,
        timeInForce: TxTimeInForce.gtc,
        validateAfter: false,
      );
      final sell = (int quantity) => state.runtime.place(
        id: _nextOrderId(state, 'FLOW-SELL'),
        ownerId: 'FLOW',
        symbol: instrument.symbol,
        side: TxSide.sell,
        kind: TxKind.market,
        quantity: quantity,
        limitPriceCents: null,
        timeInForce: TxTimeInForce.gtc,
        validateAfter: false,
      );
      if (timeKey.isEven) {
        buy(buyQuantity);
        sell(sellQuantity);
      } else {
        sell(sellQuantity);
        buy(buyQuantity);
      }
    }
  }

  /// Deterministic agent intents add prints and consume real maker depth. The
  /// agents are funded accounts, not a hidden fill source: a rejected order
  /// stays rejected and every successful print is stored by the venue.
  void _emitSmartTraderFlow(TxIndependentMarketState state, int gameDay,
      int minuteOfDay) {
    final timeKey = (gameDay - 1) * 1440 + minuteOfDay;
    const agents = <String>[
      'SMART-TREND',
      'SMART-MEAN',
      'SMART-MOMENTUM',
      'SMART-SCALPER',
    ];
    for (var index = 0; index < state.profile.instruments.length; index++) {
      final instrument = state.profile.instruments[index];
      final wave = ((gameDay * 97 + minuteOfDay * 7 + index * 31) % 41) - 20;
      final intents = <TxSide>[
        wave >= 0 ? TxSide.buy : TxSide.sell,
        wave >= 0 ? TxSide.sell : TxSide.buy,
        ((timeKey + index) % 6) < 3 ? TxSide.buy : TxSide.sell,
        ((timeKey + index) % 2) == 0 ? TxSide.buy : TxSide.sell,
      ];
      final baseQuantity = _smartTraderBaseQuantity(state.mode);
      final signalStrength = math.min(2, wave.abs() ~/ 8);
      for (var agentIndex = 0; agentIndex < agents.length; agentIndex++) {
        final ownerId = agents[agentIndex];
        if (!state.runtime.venue.accounts.containsKey(ownerId)) continue;
        final shouldTrade = switch (ownerId) {
          'SMART-TREND' => signalStrength > 0,
          'SMART-MEAN' => true,
          'SMART-MOMENTUM' => (timeKey + index) % 4 != 3,
          'SMART-SCALPER' => true,
          _ => true,
        };
        if (!shouldTrade) continue;
        final quantity = switch (ownerId) {
          'SMART-TREND' => baseQuantity + signalStrength,
          'SMART-MEAN' => baseQuantity + (signalStrength == 0 ? 1 : 0),
          'SMART-MOMENTUM' => baseQuantity +
              (((timeKey + index) % 4 == 0) ? 1 : 0),
          'SMART-SCALPER' => math.max(1, baseQuantity ~/ 2),
          _ => baseQuantity,
        };
        var side = intents[agentIndex];
        final core = state.runtime.venue.account(ownerId);
        final position = core.position(instrument.symbol);
        if (side == TxSide.sell && !instrument.supportsShort &&
            position.availableToClose < quantity) {
          side = TxSide.buy;
        }
        try {
          state.runtime.place(
            id: _nextOrderId(state, '$ownerId-${side.name}'),
            ownerId: ownerId,
            symbol: instrument.symbol,
            side: side,
            kind: TxKind.market,
            quantity: quantity,
            limitPriceCents: null,
            timeInForce: TxTimeInForce.gtc,
            validateAfter: false,
          );
        } on StateError {
          // A finite agent can run out of margin or inventory. That is a
          // visible market outcome, not permission to mint a fill.
        } on ArgumentError {
          // Keep one malformed/unsupported intent from stopping all boards.
        }
      }
    }
  }

  void _cancelMarketMakerOrders(TxIndependentMarketState state) {
    final active = state.runtime.venue.activeOrders
        .where((order) => order.ownerId == 'MM-A' || order.ownerId == 'MM-B')
        .toList();
    for (final order in active) {
      state.runtime.cancel(order.id, ownerId: order.ownerId,
          validateAfter: false);
    }
  }

  bool _ensureParticipantAccounts(TxIndependentMarketState state) {
    final profile = state.profile;
    final inventory = {
      for (final instrument in profile.instruments)
        instrument.symbol: _makerInventory(state.mode),
    };
    const ids = <String>[
      'MM-A',
      'MM-B',
      'FLOW',
      'SMART-TREND',
      'SMART-MEAN',
      'SMART-MOMENTUM',
      'SMART-SCALPER',
    ];
    var added = false;
    final marks = <String, int>{
      for (final instrument in profile.instruments)
        instrument.symbol: state.player.markPriceCents(instrument.symbol),
    };
    for (final id in ids) {
      final account = TxMarketCore(
        profile: profile,
        openingCashCents: _participantOpeningCashCents,
        initialMarks: marks,
        gameDay: state.runtime.gameDay,
        initialLongPositions: inventory,
      );
      added = state.runtime.venue.ensureAccount(id, account) || added;
    }
    return added;
  }

  int _markFor(TxMarketMode mode, int index, String symbol, int gameDay,
      int minuteOfDay, TxMarketCore player) {
    final base = switch (mode) {
      TxMarketMode.usEquity => index == 0 ? 10000 : 2500,
      TxMarketMode.futures => index == 0 ? 30000 : 12000,
      TxMarketMode.crypto => index == 0 ? 5000000 : 300000,
      TxMarketMode.forex => index == 0 ? 10800 : 15000,
      TxMarketMode.aShare => throw ArgumentError('A股不使用独立行情'),
    };
    final wave = ((gameDay * 97 + minuteOfDay * 7 + index * 31) % 41) - 20;
    final rule = TxMarketRiskRules.forMode(mode);
    final raw = base + (base * wave) ~/ 10000;
    final aligned = math.max(rule.tickSizeCents,
        (raw ~/ rule.tickSizeCents) * rule.tickSizeCents);
    // The player argument deliberately validates the resulting symbol in the
    // same account core before it is broadcast to the venue.
    player.markPriceCents(symbol);
    return aligned;
  }

  String _nextOrderId(TxIndependentMarketState state, String prefix) {
    _orderSerial++;
    // Include the last verified CAS sequence as well as a process-local
    // serial. A restored venue may have order IDs with gaps because several
    // market modes share the process serial; counting orders alone could then
    // reuse an old ID after a cold start.
    return '$prefix-${state.mode.name}-r${state.sequence}-$_orderSerial';
  }

  TxIndependentMarketState _requireState(TxMarketMode mode) {
    _validateMode(mode);
    final state = _states[mode];
    if (state == null) {
      throw StateError('Independent ${mode.name} market is not opened');
    }
    return state;
  }

  static TxMarketRuntime _freshRuntime(
      TxMarketMode mode, int gameDay, int minuteOfDay) {
    final profile = TxMarketProfile.of(mode);
    final makerInventory = _makerInventory(mode);
    final inventory = {
      for (final instrument in profile.instruments)
        instrument.symbol: makerInventory,
    };
    final accounts = <String, TxMarketCore>{
      TxIndependentMarketState.playerId:
          TxMarketCore.seeded(profile: profile),
      'MM-A': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
      'MM-B': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
      'FLOW': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
      'SMART-TREND': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
      'SMART-MEAN': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
      'SMART-MOMENTUM': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
      'SMART-SCALPER': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: _participantOpeningCashCents,
          initialLongPositions: inventory),
    };
    return TxMarketRuntime(
      venue: TxMarketVenue(profile: profile, accounts: accounts),
      gameDay: gameDay,
      minuteOfDay: minuteOfDay,
    );
  }

  // FX contracts carry a 100,000-unit multiplier. A 120-lot seeded inventory
  // must remain comfortably inside cross-margin equity so the finite makers
  // can actually quote and recycle both sides of the book on the first open.
  // This is collateral, not synthetic liquidity: every fill still passes the
  // account's margin and inventory checks and the balance is persisted.
  static const _participantOpeningCashCents = 12000000000;

  static int _makerInventory(TxMarketMode mode) => switch (mode) {
    // These are finite, but large enough that a few directional minutes do
    // not make every simulated participant disappear from the book. The
    // venue still rejects a side when an account truly exhausts its risk
    // budget; this is not an infinite-liquidity shortcut.
    TxMarketMode.usEquity => 4800,
    TxMarketMode.futures => 480,
    TxMarketMode.crypto => 1200,
    // One standard lot is large notional in this model. Keep a finite but
    // usable seed so the FX book can absorb a directional pulse.
    TxMarketMode.forex => 120,
    TxMarketMode.aShare => 0,
  };

  static int _makerQuoteBaseQuantity(TxMarketMode mode) => switch (mode) {
    // Two makers share the inside level. A player-sized order remains inside
    // the first level, while the deterministic FLOW/AI pulses can legitimately
    // consume several levels and create real OHLC high/low variation.
    TxMarketMode.usEquity => 10,
    TxMarketMode.futures => 3,
    TxMarketMode.crypto => 8,
    TxMarketMode.forex => 2,
    TxMarketMode.aShare => 0,
  };

  static int _flowOrderQuantity(TxMarketMode mode) => switch (mode) {
    TxMarketMode.usEquity => 8,
    TxMarketMode.futures => 2,
    TxMarketMode.crypto => 2,
    TxMarketMode.forex => 2,
    TxMarketMode.aShare => 0,
  };

  static int _smartTraderBaseQuantity(TxMarketMode mode) => switch (mode) {
    TxMarketMode.usEquity => 8,
    TxMarketMode.futures => 2,
    TxMarketMode.crypto => 5,
    TxMarketMode.forex => 2,
    TxMarketMode.aShare => 0,
  };

  static int _flowPressureStep(TxMarketMode mode) => switch (mode) {
    TxMarketMode.usEquity => 6,
    TxMarketMode.futures => 1,
    TxMarketMode.crypto => 12,
    TxMarketMode.forex => 1,
    TxMarketMode.aShare => 0,
  };

  static int _quoteSpreadBps(TxMarketMode mode) => switch (mode) {
    TxMarketMode.usEquity => 2,
    TxMarketMode.futures => 2,
    TxMarketMode.crypto => 2,
    TxMarketMode.forex => 2,
    TxMarketMode.aShare => 0,
  };

  static void _validateMode(TxMarketMode mode) {
    if (mode == TxMarketMode.aShare) {
      throw ArgumentError('A股继续使用 Rust 已连接现货账本');
    }
  }

  static void _validateClock(int gameDay, int minuteOfDay) {
    if (gameDay < 1 || minuteOfDay < 0 || minuteOfDay >= 1440) {
      throw ArgumentError('Invalid independent market clock');
    }
  }
}

class _CandleDraft {
  _CandleDraft({required int priceCents})
      : openCents = priceCents,
        highCents = priceCents,
        lowCents = priceCents,
        closeCents = priceCents;

  final int openCents;
  int highCents;
  int lowCents;
  int closeCents;
  int volume = 0;
}
