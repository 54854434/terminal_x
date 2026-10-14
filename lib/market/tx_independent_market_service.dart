import 'dart:async';
import 'dart:math' as math;

import '../engine/tx_engine.dart';
import '../storage/tx_sqlite_store.dart';
import 'tx_candle_history.dart';
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

  TxMarketCore get player => runtime.venue.account(playerId);

  TxMarketRiskSnapshot get playerRisk => player.snapshot();

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
      final byStep = <int, _CandleDraft>{};
      for (final fill in runtime.venue.fills.where(
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
}

/// Serialized adapter for all independent market modes.
///
/// Every public mutation is queued. A player order, a quote refresh and a
/// market-clock advance therefore share one SQLite CAS boundary instead of
/// racing one another when the user changes tabs or returns from background.
class TxIndependentMarketService {
  TxIndependentMarketService(this.database);

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
  }) => _enqueue(() async {
        _validateMode(mode);
        final existing = _states[mode];
        if (existing != null) {
          await _syncUnlocked(existing, gameDay, minuteOfDay);
          return existing;
        }

        final stored = await database.readMarketRuntime(mode);
        late final TxIndependentMarketState next;
        if (stored == null) {
          next = TxIndependentMarketState._(
            mode: mode,
            runtime: _freshRuntime(mode, gameDay, minuteOfDay),
            sequence: 0,
          );
          _states[mode] = next;
          try {
            await _syncUnlocked(next, gameDay, minuteOfDay, force: true);
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

  Future<void> _syncUnlocked(TxIndependentMarketState state, int gameDay,
      int minuteOfDay, {bool force = false}) async {
    _validateClock(gameDay, minuteOfDay);
    final runtime = state.runtime;
    final moved = gameDay > runtime.gameDay ||
        (gameDay == runtime.gameDay && minuteOfDay > runtime.minuteOfDay);
    if (!moved && !force) return;
    if (moved) {
      runtime.advanceClock(
          nextGameDay: gameDay, nextMinuteOfDay: minuteOfDay);
    }
    final status = state.profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    if (status.isOpen) {
      for (var index = 0; index < state.profile.instruments.length; index++) {
        final instrument = state.profile.instruments[index];
        final price = _markFor(
            state.mode, index, instrument.symbol, gameDay, minuteOfDay,
            runtime.venue.account(TxIndependentMarketState.playerId));
        runtime.markToMarket(symbol: instrument.symbol, priceCents: price);
      }
      _refreshQuotes(state, gameDay, minuteOfDay);
      _emitSyntheticFlow(state, gameDay, minuteOfDay);
    } else {
      _cancelMarketMakerOrders(state);
    }
    await _save(state);
  }

  Future<void> _save(TxIndependentMarketState state) async {
    final saved = await database.saveMarketRuntime(state.runtime,
        expectedSequence: state.sequence);
    state.sequence = saved.sequence;
    state.runtime = saved.runtime;
    state._rebuildCandles();
  }

  void _refreshQuotes(TxIndependentMarketState state, int gameDay,
      int minuteOfDay) {
    _cancelMarketMakerOrders(state);
    final rule = TxMarketRiskRules.forMode(state.mode);
    for (var index = 0; index < state.profile.instruments.length; index++) {
      final instrument = state.profile.instruments[index];
      final mark = state.player.markPriceCents(instrument.symbol);
      final spread = math.max(rule.tickSizeCents * 2, mark ~/ 1000);
      final quantity = switch (state.mode) {
        TxMarketMode.futures => 2,
        TxMarketMode.forex => 1,
        TxMarketMode.crypto => 1,
        _ => 10,
      };
      for (var level = 0; level < 3; level++) {
        final distance = spread * (level + 1);
        final bid = math.max(rule.tickSizeCents, mark - distance);
        final ask = mark + distance;
        state.runtime.place(
          id: _nextOrderId(state, 'MM-B'),
          ownerId: 'MM-B',
          symbol: instrument.symbol,
          side: TxSide.buy,
          kind: TxKind.limit,
          quantity: quantity + level,
          limitPriceCents: bid,
          timeInForce: TxTimeInForce.gtc,
        );
        state.runtime.place(
          id: _nextOrderId(state, 'MM-A'),
          ownerId: 'MM-A',
          symbol: instrument.symbol,
          side: TxSide.sell,
          kind: TxKind.limit,
          quantity: quantity + level,
          limitPriceCents: ask,
          timeInForce: TxTimeInForce.gtc,
        );
      }
    }
  }

  void _emitSyntheticFlow(TxIndependentMarketState state, int gameDay,
      int minuteOfDay) {
    final timeKey = (gameDay - 1) * 1440 + minuteOfDay;
    if (state.runtime.venue.fills.isNotEmpty && timeKey % 3 != 0) return;
    final index = timeKey.abs() % state.profile.instruments.length;
    final instrument = state.profile.instruments[index];
    final side = timeKey.isEven ? TxSide.buy : TxSide.sell;
    state.runtime.place(
      id: _nextOrderId(state, 'FLOW'),
      ownerId: 'FLOW',
      symbol: instrument.symbol,
      side: side,
      kind: TxKind.market,
      quantity: 1,
      limitPriceCents: null,
      timeInForce: TxTimeInForce.gtc,
    );
  }

  void _cancelMarketMakerOrders(TxIndependentMarketState state) {
    final active = state.runtime.venue.activeOrders
        .where((order) => order.ownerId == 'MM-A' || order.ownerId == 'MM-B')
        .toList();
    for (final order in active) {
      state.runtime.cancel(order.id, ownerId: order.ownerId);
    }
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
    final makerInventory = switch (mode) {
      TxMarketMode.usEquity => 1000,
      TxMarketMode.futures => 10,
      TxMarketMode.crypto => 10,
      TxMarketMode.forex => 5,
      TxMarketMode.aShare => 0,
    };
    final inventory = {
      for (final instrument in profile.instruments)
        instrument.symbol: makerInventory,
    };
    final accounts = <String, TxMarketCore>{
      TxIndependentMarketState.playerId:
          TxMarketCore.seeded(profile: profile),
      'MM-A': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: 500000000,
          initialLongPositions: inventory),
      'MM-B': TxMarketCore.seeded(profile: profile, openingCashCents: 500000000),
      'FLOW': TxMarketCore.seeded(
          profile: profile,
          openingCashCents: 500000000,
          initialLongPositions: inventory),
    };
    return TxMarketRuntime(
      venue: TxMarketVenue(profile: profile, accounts: accounts),
      gameDay: gameDay,
      minuteOfDay: minuteOfDay,
    );
  }

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
