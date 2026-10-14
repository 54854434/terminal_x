import 'dart:convert';

import '../engine/tx_engine.dart';
import 'tx_market_instruments.dart';
import 'tx_market_profiles.dart';

/// Numeric risk rules for the five simulated market modes.
///
/// The existing A-share [TxEngine] remains the connected order-book core. This
/// model is the independent account/risk boundary for the other modes and is
/// deliberately deterministic: it accepts a validated execution or mark and
/// never invents a fill, quote, fee or external price.
class TxMarketRiskRule {
  const TxMarketRiskRule({
    required this.mode,
    required this.usesMargin,
    required this.supportsShort,
    required this.tPlusOne,
    required this.initialMarginBps,
    required this.maintenanceMarginBps,
      required this.shortBorrowBpsPerDay,
      required this.fundingBpsPerDay,
      required this.rolloverBpsPerDay,
    required this.contractMultiplier,
    required this.lotSize,
    required this.tickSizeCents,
    required this.leverageLabel,
  });

  final TxMarketMode mode;
  final bool usesMargin;
  final bool supportsShort;
  final bool tPlusOne;
  final int initialMarginBps;
  final int maintenanceMarginBps;
  final int shortBorrowBpsPerDay;
  final int fundingBpsPerDay;
  final int rolloverBpsPerDay;
  final int contractMultiplier;
  final int lotSize;
  final int tickSizeCents;
  final String leverageLabel;

  int notionalCents({required int priceCents, required int quantity}) {
    _validatePrice(priceCents);
    if (quantity < 1 || quantity > TxEngine.maxQuantity) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    if (quantity > TxEngine.maxNotionalCents ~/ priceCents ||
        quantity > TxEngine.maxNotionalCents ~/ priceCents ~/ contractMultiplier) {
      throw ArgumentError('Market notional exceeds engine limit');
    }
    return priceCents * quantity * contractMultiplier;
  }

  int initialMarginCents({required int priceCents, required int quantity}) =>
      _margin(notionalCents(priceCents: priceCents, quantity: quantity),
          initialMarginBps);

  int maintenanceMarginCents({required int priceCents, required int quantity}) =>
      _margin(notionalCents(priceCents: priceCents, quantity: quantity),
          maintenanceMarginBps);

  void validateQuantity(int quantity) {
    if (quantity < 1 || quantity > TxEngine.maxQuantity ||
        quantity % lotSize != 0) {
      throw ArgumentError.value(quantity, 'quantity',
          'Must be a positive multiple of $lotSize');
    }
  }

  void validatePrice(int priceCents) => _validatePrice(priceCents);

  void _validatePrice(int priceCents) {
    if (priceCents < 1 || priceCents > TxEngine.maxPriceCents ||
        priceCents % tickSizeCents != 0) {
      throw ArgumentError.value(priceCents, 'priceCents',
          'Price must be a positive multiple of $tickSizeCents');
    }
  }

  static int _margin(int notionalCents, int basisPoints) {
    if (notionalCents < 0 || basisPoints < 0 || basisPoints > 10000) {
      throw ArgumentError('Invalid margin input');
    }
    return (notionalCents * basisPoints + 9999) ~/ 10000;
  }
}

class TxMarketRiskRules {
  const TxMarketRiskRules._();

  static const aShare = TxMarketRiskRule(
    mode: TxMarketMode.aShare,
    usesMargin: false,
    supportsShort: false,
    tPlusOne: true,
    initialMarginBps: 10000,
    maintenanceMarginBps: 10000,
    shortBorrowBpsPerDay: 0,
    fundingBpsPerDay: 0,
    rolloverBpsPerDay: 0,
    contractMultiplier: 1,
    lotSize: 1,
    tickSizeCents: 1,
    leverageLabel: '1×',
  );

  static const usEquity = TxMarketRiskRule(
    mode: TxMarketMode.usEquity,
    usesMargin: true,
    supportsShort: true,
    tPlusOne: false,
    initialMarginBps: 5000,
    maintenanceMarginBps: 2500,
    shortBorrowBpsPerDay: 2,
    fundingBpsPerDay: 0,
    rolloverBpsPerDay: 0,
    contractMultiplier: 1,
    lotSize: 1,
    tickSizeCents: 1,
    leverageLabel: '2×',
  );

  static const futures = TxMarketRiskRule(
    mode: TxMarketMode.futures,
    usesMargin: true,
    supportsShort: true,
    tPlusOne: false,
    initialMarginBps: 1000,
    maintenanceMarginBps: 750,
    shortBorrowBpsPerDay: 0,
    fundingBpsPerDay: 0,
    rolloverBpsPerDay: 0,
    contractMultiplier: 300,
    lotSize: 1,
    tickSizeCents: 1,
    leverageLabel: '10×',
  );

  static const crypto = TxMarketRiskRule(
    mode: TxMarketMode.crypto,
    usesMargin: true,
    supportsShort: true,
    tPlusOne: false,
    initialMarginBps: 500,
    maintenanceMarginBps: 250,
    shortBorrowBpsPerDay: 0,
    fundingBpsPerDay: 1,
    rolloverBpsPerDay: 0,
    contractMultiplier: 1,
    lotSize: 1,
    tickSizeCents: 1,
    leverageLabel: '20×',
  );

  static const forex = TxMarketRiskRule(
    mode: TxMarketMode.forex,
    usesMargin: true,
    supportsShort: true,
    tPlusOne: false,
    initialMarginBps: 334,
    maintenanceMarginBps: 167,
    shortBorrowBpsPerDay: 0,
    fundingBpsPerDay: 0,
    rolloverBpsPerDay: 1,
    contractMultiplier: 100000,
    lotSize: 1,
    tickSizeCents: 1,
    leverageLabel: '约 30×',
  );

  static const values = <TxMarketRiskRule>[
    aShare, usEquity, futures, crypto, forex,
  ];

  static TxMarketRiskRule forMode(TxMarketMode mode) => values.firstWhere(
      (rule) => rule.mode == mode);
}

/// Immutable position projection. [netQuantity] is signed: positive is long,
/// negative is short. [unsettledLongQuantity] is the A-share T+1 portion.
class TxMarketPosition {
  const TxMarketPosition({
    required this.symbol,
    required this.netQuantity,
    required this.averageEntryCents,
    required this.unsettledLongQuantity,
    required this.realizedPnlCents,
  });

  final String symbol;
  final int netQuantity;
  final int averageEntryCents;
  final int unsettledLongQuantity;
  final int realizedPnlCents;

  int get longQuantity => netQuantity > 0 ? netQuantity : 0;
  int get shortQuantity => netQuantity < 0 ? -netQuantity : 0;
  int get availableToClose => netQuantity > 0
      ? netQuantity - unsettledLongQuantity
      : shortQuantity;
  bool get isFlat => netQuantity == 0;
}

class TxMarketRiskSnapshot {
  const TxMarketRiskSnapshot({
    required this.cashCents,
    required this.equityCents,
    required this.unrealizedPnlCents,
    required this.realizedPnlCents,
    required this.usedMarginCents,
    required this.maintenanceMarginCents,
    required this.freeMarginCents,
    required this.marginRatio,
    required this.liquidationRequired,
    required this.positions,
  });

  final int cashCents;
  final int equityCents;
  final int unrealizedPnlCents;
  final int realizedPnlCents;
  final int usedMarginCents;
  final int maintenanceMarginCents;
  final int freeMarginCents;
  final double? marginRatio;
  final bool liquidationRequired;
  final Map<String, TxMarketPosition> positions;

  bool get hasPositions => positions.values.any((position) => !position.isFlat);
}

/// Explicit end-of-day accounting result. Intraday marks remain read-only;
/// callers must deliberately invoke [TxMarketCore.settleDay] to realize
/// futures mark-to-market and charge the market's overnight carrying rules.
class TxMarketSettlement {
  const TxMarketSettlement({
    required this.fromGameDay,
    required this.toGameDay,
    required this.days,
    required this.markToMarketPnlCents,
    required this.financingPnlCents,
    required this.cashCents,
    required this.risk,
  });

  final int fromGameDay;
  final int toGameDay;
  final int days;
  final int markToMarketPnlCents;
  /// Negative means a cost; positive means a funding/rollover credit.
  final int financingPnlCents;
  final int cashCents;
  final TxMarketRiskSnapshot risk;
}

class TxMarketExecutionPlan {
  const TxMarketExecutionPlan({
    required this.accepted,
    required this.reason,
    required this.side,
    required this.requestedQuantity,
    required this.closingQuantity,
    required this.openingQuantity,
    required this.realizedPnlCents,
    required this.feeCents,
    required this.projectedCashCents,
    required this.projectedUsedMarginCents,
    required this.projectedEquityCents,
    required this.projectedPosition,
  });

  final bool accepted;
  final String? reason;
  final TxSide side;
  final int requestedQuantity;
  final int closingQuantity;
  final int openingQuantity;
  final int realizedPnlCents;
  final int feeCents;
  final int projectedCashCents;
  final int projectedUsedMarginCents;
  final int projectedEquityCents;
  final TxMarketPosition projectedPosition;
}

class TxMarketExecutionResult {
  const TxMarketExecutionResult({
    required this.side,
    required this.quantity,
    required this.closingQuantity,
    required this.openingQuantity,
    required this.realizedPnlCents,
    required this.feeCents,
    required this.position,
    required this.risk,
  });

  final TxSide side;
  final int quantity;
  final int closingQuantity;
  final int openingQuantity;
  final int realizedPnlCents;
  final int feeCents;
  final TxMarketPosition position;
  final TxMarketRiskSnapshot risk;
}

class TxMarketCore {
  static const snapshotSchema = 1;

  TxMarketCore({
    required this.profile,
    required int openingCashCents,
    required Map<String, int> initialMarks,
    this.gameDay = 1,
  }) : cashCents = openingCashCents,
       rule = TxMarketRiskRules.forMode(profile.mode),
       _marks = Map<String, int>.from(initialMarks) {
    if (openingCashCents < 0 || gameDay < 1) {
      throw ArgumentError('Invalid opening cash or game day');
    }
    final symbols = profile.instruments.map((item) => item.symbol).toSet();
    if (symbols.length != profile.instruments.length ||
        _marks.keys.length != symbols.length ||
        !_marks.keys.every(symbols.contains)) {
      throw ArgumentError('Initial marks must cover every market instrument');
    }
    for (final entry in _marks.entries) {
      _ruleFor(entry.key).validatePrice(entry.value);
    }
  }

  final TxMarketProfile profile;
  final TxMarketRiskRule rule;
  int cashCents;
  int gameDay;
  final Map<String, int> _marks;
  final Map<String, _MutablePosition> _positions = {};
  int _realizedPnlCents = 0;

  static TxMarketCore seeded({
    required TxMarketProfile profile,
    int openingCashCents = 100000000,
    int gameDay = 1,
  }) => TxMarketCore(
        profile: profile,
        openingCashCents: openingCashCents,
        gameDay: gameDay,
        initialMarks: {
          for (var i = 0; i < profile.instruments.length; i++)
            profile.instruments[i].symbol: _defaultMark(profile.mode, i),
        },
      );

  int markPriceCents(String symbol) {
    _requireSymbol(symbol);
    return _marks[symbol]!;
  }

  Map<String, TxMarketPosition> get positions => Map.unmodifiable({
        for (final entry in _positions.entries) entry.key: entry.value.freeze(),
      });

  TxMarketPosition position(String symbol) {
    _requireSymbol(symbol);
    return (_positions[symbol] ?? _MutablePosition(symbol: symbol)).freeze();
  }

  void markToMarket({required String symbol, required int priceCents}) {
    _requireSymbol(symbol);
    _ruleFor(symbol).validatePrice(priceCents);
    _marks[symbol] = priceCents;
  }

  void advanceGameDay(int nextGameDay) {
    if (nextGameDay < gameDay) {
      throw ArgumentError.value(nextGameDay, 'nextGameDay');
    }
    if (nextGameDay == gameDay) return;
    gameDay = nextGameDay;
    for (final position in _positions.values) {
      if (_ruleFor(position.symbol).tPlusOne) {
        position.unsettledLongQuantity = 0;
      }
    }
  }

  /// Applies explicit multi-day carrying and settlement rules.
  ///
  /// This method is intentionally separate from [advanceGameDay]: a caller
  /// can move the simulation clock during a preview without silently charging
  /// a position. Futures realize mark-to-market at the current mark; equity
  /// shorts pay borrow; crypto perpetuals pay/receive funding; forex open
  /// positions pay the simplified rollover rate. Spot A-share positions only
  /// release their T+1 quantity.
  TxMarketSettlement settleDay({required int nextGameDay}) {
    if (nextGameDay <= gameDay) {
      throw ArgumentError.value(nextGameDay, 'nextGameDay',
          'Settlement must advance the game day');
    }
    final from = gameDay;
    final days = nextGameDay - gameDay;
    var markToMarket = 0;
    var financing = 0;
    for (final entry in _positions.entries) {
      final position = entry.value;
      if (position.netQuantity == 0) continue;
      final positionRule = _ruleFor(entry.key);
      final mark = _marks[entry.key]!;
      if (profile.mode == TxMarketMode.futures) {
        final pnl = (mark - position.averageEntryCents) *
            position.netQuantity * positionRule.contractMultiplier;
        cashCents += pnl;
        position.realizedPnlCents += pnl;
        _realizedPnlCents += pnl;
        markToMarket += pnl;
        position.averageEntryCents = mark;
      }
      final notional = mark * position.netQuantity.abs() *
          positionRule.contractMultiplier;
      var dailyBps = 0;
      var fundingSign = -1;
      if (profile.mode == TxMarketMode.usEquity && position.netQuantity < 0) {
        dailyBps = positionRule.shortBorrowBpsPerDay;
      } else if (profile.mode == TxMarketMode.crypto &&
          entry.key == 'SIM-BTCUSDT') {
        dailyBps = positionRule.fundingBpsPerDay;
        fundingSign = position.netQuantity > 0 ? -1 : 1;
      } else if (profile.mode == TxMarketMode.forex) {
        dailyBps = positionRule.rolloverBpsPerDay;
      }
      if (dailyBps > 0) {
        final amount = (notional * dailyBps * days + 9999) ~/ 10000;
        final adjustment = amount * fundingSign;
        cashCents += adjustment;
        financing += adjustment;
      }
      if (positionRule.tPlusOne) position.unsettledLongQuantity = 0;
    }
    gameDay = nextGameDay;
    return TxMarketSettlement(
      fromGameDay: from,
      toGameDay: nextGameDay,
      days: days,
      markToMarketPnlCents: markToMarket,
      financingPnlCents: financing,
      cashCents: cashCents,
      risk: snapshot(),
    );
  }

  TxMarketRiskSnapshot snapshot() => _snapshot(
        cash: cashCents,
        positions: _positions,
        markOverrides: const {},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': snapshotSchema,
        'mode': profile.mode.name,
        'cashCents': cashCents,
        'gameDay': gameDay,
        'marks': _marks,
        'realizedPnlCents': _realizedPnlCents,
        'positions': [
          for (final position in _positions.values)
            <String, dynamic>{
              'symbol': position.symbol,
              'netQuantity': position.netQuantity,
              'averageEntryCents': position.averageEntryCents,
              'unsettledLongQuantity': position.unsettledLongQuantity,
              'realizedPnlCents': position.realizedPnlCents,
            },
        ],
      };

  String exportJson() => jsonEncode(toJson());

  static TxMarketCore fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid market core JSON');
    return fromJsonMap(Map<String, dynamic>.from(decoded));
  }

  static TxMarketCore fromJsonMap(Map<String, dynamic> data) {
    if (data['schema'] != snapshotSchema || data['mode'] is! String ||
        data['cashCents'] is! int || data['gameDay'] is! int ||
        data['marks'] is! Map || data['positions'] is! List ||
        data['realizedPnlCents'] is! int) {
      throw const FormatException('Invalid market core snapshot');
    }
    final mode = TxMarketMode.values.firstWhere(
        (value) => value.name == data['mode'],
        orElse: () => throw const FormatException('Unknown market mode'));
    final profile = TxMarketProfile.of(mode);
    final marks = <String, int>{};
    for (final entry in (data['marks'] as Map).entries) {
      if (entry.key is! String || entry.value is! int) {
        throw const FormatException('Invalid market mark');
      }
      marks[entry.key as String] = entry.value as int;
    }
    final core = TxMarketCore(
      profile: profile,
      openingCashCents: data['cashCents'] as int,
      initialMarks: marks,
      gameDay: data['gameDay'] as int,
    )
      ..cashCents = data['cashCents'] as int
      .._realizedPnlCents = data['realizedPnlCents'] as int;
    final seen = <String>{};
    for (final rawPosition in data['positions'] as List) {
      if (rawPosition is! Map) {
        throw const FormatException('Invalid market position');
      }
      final position = Map<String, dynamic>.from(rawPosition);
      if (position['symbol'] is! String || position['netQuantity'] is! int ||
          position['averageEntryCents'] is! int ||
          position['unsettledLongQuantity'] is! int ||
          position['realizedPnlCents'] is! int) {
        throw const FormatException('Invalid market position fields');
      }
      final symbol = position['symbol'] as String;
      if (!seen.add(symbol)) throw const FormatException('Duplicate position');
      core._requireSymbol(symbol);
      final positionRule = core._ruleFor(symbol);
      final net = position['netQuantity'] as int;
      final average = position['averageEntryCents'] as int;
      final unsettled = position['unsettledLongQuantity'] as int;
      if (net.abs() > TxEngine.maxQuantity ||
          (net == 0 && average != 0) ||
          (net != 0 && (average < 1 || average > TxEngine.maxPriceCents)) ||
          unsettled < 0 || unsettled > (net > 0 ? net : 0) ||
          (!positionRule.supportsShort && net < 0) ||
          (!positionRule.tPlusOne && unsettled != 0)) {
        throw const FormatException('Invalid market position invariant');
      }
      core._positions[symbol] = _MutablePosition(symbol: symbol)
        ..netQuantity = net
        ..averageEntryCents = average
        ..unsettledLongQuantity = unsettled
        ..realizedPnlCents = position['realizedPnlCents'] as int;
    }
    core.snapshot();
    return core;
  }

  /// Creates an isolated candidate for venue-level atomic preflight. The
  /// candidate has no shared mutable account, mark or position state.
  TxMarketCore fork() {
    final copy = TxMarketCore(
      profile: profile,
      openingCashCents: cashCents,
      initialMarks: _marks,
      gameDay: gameDay,
    )..cashCents = cashCents;
    copy._realizedPnlCents = _realizedPnlCents;
    for (final entry in _positions.entries) {
      copy._positions[entry.key] = entry.value.copy();
    }
    return copy;
  }

  /// Commits a previously preflighted fork. It is intentionally explicit so
  /// a venue can apply all legs of a multi-account match atomically.
  void commitFork(TxMarketCore fork) {
    final expectedSymbols = profile.instruments.map((item) => item.symbol).toSet();
    final forkSymbols = fork.profile.instruments.map((item) => item.symbol).toSet();
    if (fork.profile.mode != profile.mode ||
        expectedSymbols.length != forkSymbols.length ||
        !forkSymbols.every(expectedSymbols.contains)) {
      throw StateError('Cannot commit a different market core');
    }
    cashCents = fork.cashCents;
    gameDay = fork.gameDay;
    _marks
      ..clear()
      ..addAll(fork._marks);
    _positions
      ..clear()
      ..addAll({
        for (final entry in fork._positions.entries) entry.key: entry.value.copy(),
      });
    _realizedPnlCents = fork._realizedPnlCents;
  }

  TxMarketExecutionPlan preview({
    required String symbol,
    required TxSide side,
    required int quantity,
    required int priceCents,
    required int gameDay,
    required int minuteOfDay,
    bool reduceOnly = false,
    int feeCents = 0,
  }) => _calculate(
        symbol: symbol,
        side: side,
        quantity: quantity,
        priceCents: priceCents,
        gameDay: gameDay,
        minuteOfDay: minuteOfDay,
        reduceOnly: reduceOnly,
        feeCents: feeCents,
      ).publicPlan;

  TxMarketExecutionResult applyExecution({
    required String symbol,
    required TxSide side,
    required int quantity,
    required int priceCents,
    required int gameDay,
    required int minuteOfDay,
    bool reduceOnly = false,
    int feeCents = 0,
  }) => _applyExecution(
        symbol: symbol,
        side: side,
        quantity: quantity,
        priceCents: priceCents,
        gameDay: gameDay,
        minuteOfDay: minuteOfDay,
        reduceOnly: reduceOnly,
        feeCents: feeCents,
        ignoreSession: false,
      );

  TxMarketExecutionResult _applyExecution({
    required String symbol,
    required TxSide side,
    required int quantity,
    required int priceCents,
    required int gameDay,
    required int minuteOfDay,
    required bool reduceOnly,
    int feeCents = 0,
    required bool ignoreSession,
  }) {
    final calculated = _calculate(
      symbol: symbol,
      side: side,
      quantity: quantity,
      priceCents: priceCents,
      gameDay: gameDay,
      minuteOfDay: minuteOfDay,
      reduceOnly: reduceOnly,
      feeCents: feeCents,
      ignoreSession: ignoreSession,
    );
    if (!calculated.publicPlan.accepted) {
      throw StateError(calculated.publicPlan.reason!);
    }
    final state = _positions.putIfAbsent(
        symbol, () => _MutablePosition(symbol: symbol));
    state.netQuantity = calculated.newQuantity;
    state.averageEntryCents = calculated.newAverageEntryCents;
    state.unsettledLongQuantity = calculated.newUnsettledLongQuantity;
    state.realizedPnlCents += calculated.realizedPnlCents;
    _realizedPnlCents += calculated.realizedPnlCents;
    cashCents = calculated.projectedCashCents;
    _marks[symbol] = priceCents;
    return TxMarketExecutionResult(
      side: side,
      quantity: quantity,
      closingQuantity: calculated.closingQuantity,
      openingQuantity: calculated.openingQuantity,
      realizedPnlCents: calculated.realizedPnlCents,
      feeCents: calculated.feeCents,
      position: state.freeze(),
      risk: snapshot(),
    );
  }

  /// System liquidation uses the latest mark and bypasses the entry gate.
  /// It is intentionally explicit: the independent core does not invent
  /// order-book liquidity or claim a slippage model that is not present yet.
  List<TxMarketExecutionResult> forceLiquidate() {
    if (!snapshot().liquidationRequired) return const [];
    final results = <TxMarketExecutionResult>[];
    for (final entry in _positions.entries.toList()) {
      final quantity = entry.value.netQuantity.abs();
      if (quantity == 0) continue;
      results.add(_applyExecution(
        symbol: entry.key,
        side: entry.value.netQuantity > 0 ? TxSide.sell : TxSide.buy,
        quantity: quantity,
        priceCents: _marks[entry.key]!,
        gameDay: gameDay,
        minuteOfDay: 0,
        reduceOnly: true,
        ignoreSession: true,
      ));
    }
    return List<TxMarketExecutionResult>.unmodifiable(results);
  }

  _CalculatedExecution _calculate({
    required String symbol,
    required TxSide side,
    required int quantity,
    required int priceCents,
    required int gameDay,
    required int minuteOfDay,
    required bool reduceOnly,
    int feeCents = 0,
    bool ignoreSession = false,
  }) {
    _requireSymbol(symbol);
    final current = _positions[symbol] ?? _MutablePosition(symbol: symbol);
    final tradeRule = _ruleFor(symbol);
    final fallback = _CalculatedExecution.rejected(
      side: side,
      quantity: quantity,
      current: current,
      feeCents: feeCents,
    );
    if (gameDay < 1 || minuteOfDay < 0 || minuteOfDay >= 1440) {
      return fallback.withReason('无效的交易时间');
    }
    if (!ignoreSession) {
      final status = profile.schedule.status(
          gameDay: gameDay, minuteOfDay: minuteOfDay);
      if (!status.isOpen) return fallback.withReason('${status.label}，当前不可成交');
    }
    try {
      if (feeCents < 0 || feeCents > TxEngine.maxNotionalCents) {
        return fallback.withReason('无效的成交费用');
      }
      tradeRule.validateQuantity(quantity);
      tradeRule.validatePrice(priceCents);
      tradeRule.notionalCents(priceCents: priceCents, quantity: quantity);
    } on ArgumentError catch (error) {
      return fallback.withReason(error.message.toString());
    }

    final signedDelta = side == TxSide.buy ? quantity : -quantity;
    if (!tradeRule.supportsShort && signedDelta < 0 &&
        quantity > current.availableToClose) {
      return fallback.withReason(tradeRule.tPlusOne
          ? 'T+1 可卖数量不足：可卖 ${current.availableToClose}'
          : '可平仓数量不足：可用 ${current.availableToClose}');
    }
    if (!tradeRule.supportsShort && current.netQuantity + signedDelta < 0) {
      return fallback.withReason('当前市场规则不支持做空');
    }

    final transition = _transition(
        current, signedDelta, priceCents, tradeRule);
    if (reduceOnly && transition.openingQuantity > 0) {
      return fallback.withReason('只减仓委托不能增加或反向开仓');
    }
    final projectedPositions = <String, _MutablePosition>{
      for (final entry in _positions.entries)
        entry.key: entry.value.copy(),
    };
    projectedPositions[symbol] = transition.position;
    final notional = tradeRule.notionalCents(
        priceCents: priceCents, quantity: quantity);
    final projectedCash = tradeRule.usesMargin
        ? cashCents + transition.realizedPnlCents - feeCents
        : cashCents + (side == TxSide.buy ? -notional : notional) - feeCents;
    final projectedUsedMargin = _usedMargin(
        positions: projectedPositions, markOverrides: {symbol: priceCents});
    final projectedEquity = _snapshot(
      cash: projectedCash,
      positions: projectedPositions,
      markOverrides: {symbol: priceCents},
    ).equityCents;
    if (!tradeRule.usesMargin && projectedCash < 0) {
      return fallback.withReason('可用现金不足');
    }
    final currentRisk = snapshot();
    if (tradeRule.usesMargin && currentRisk.liquidationRequired &&
        transition.openingQuantity > 0) {
      return fallback.withReason('保证金不足，仅允许减仓或强平');
    }
    if (tradeRule.usesMargin && projectedCash < projectedUsedMargin) {
      return fallback.withReason('保证金不足，需要至少 $projectedUsedMargin');
    }
    return _CalculatedExecution.accepted(
      side: side,
      quantity: quantity,
      position: transition.position,
      closingQuantity: transition.closingQuantity,
      openingQuantity: transition.openingQuantity,
      realizedPnlCents: transition.realizedPnlCents,
      feeCents: feeCents,
      projectedCashCents: projectedCash,
      projectedUsedMarginCents: projectedUsedMargin,
      projectedEquityCents: projectedEquity,
    );
  }

  _PositionTransition _transition(
      _MutablePosition current,
      int signedDelta,
      int priceCents,
      TxMarketRiskRule tradeRule) {
    final oldQuantity = current.netQuantity;
    if (oldQuantity == 0 || oldQuantity.sign == signedDelta.sign) {
      final oldAbs = oldQuantity.abs();
      final newAbs = oldAbs + signedDelta.abs();
      final average = oldAbs == 0
          ? priceCents
          : (oldAbs * current.averageEntryCents +
                  signedDelta.abs() * priceCents) ~/ newAbs;
      final position = current.copy()
        ..netQuantity = oldQuantity + signedDelta
        ..averageEntryCents = average
        ..unsettledLongQuantity = tradeRule.tPlusOne
            ? current.unsettledLongQuantity +
                (signedDelta > 0 ? signedDelta : 0)
            : 0;
      return _PositionTransition(
        position: position,
        closingQuantity: 0,
        openingQuantity: signedDelta.abs(),
        realizedPnlCents: 0,
      );
    }
    final closing = oldQuantity.abs() < signedDelta.abs()
        ? oldQuantity.abs() : signedDelta.abs();
    final realized = oldQuantity > 0
        ? (priceCents - current.averageEntryCents) * closing *
            tradeRule.contractMultiplier
        : (current.averageEntryCents - priceCents) * closing *
            tradeRule.contractMultiplier;
    final remainder = signedDelta.abs() - closing;
    final position = current.copy();
    if (remainder == 0) {
      position.netQuantity = oldQuantity + signedDelta;
      position.averageEntryCents = position.netQuantity == 0
          ? 0 : current.averageEntryCents;
      if (position.netQuantity == 0) position.unsettledLongQuantity = 0;
    } else {
      position.netQuantity = signedDelta.sign * remainder;
      position.averageEntryCents = priceCents;
      position.unsettledLongQuantity = tradeRule.tPlusOne && position.netQuantity > 0
          ? remainder : 0;
    }
    return _PositionTransition(
      position: position,
      closingQuantity: closing,
      openingQuantity: remainder,
      realizedPnlCents: realized,
    );
  }

  TxMarketRiskSnapshot _snapshot({
    required int cash,
    required Map<String, _MutablePosition> positions,
    required Map<String, int> markOverrides,
  }) {
    var unrealized = 0;
    var marginUnrealized = 0;
    var used = 0;
    var maintenance = 0;
    var spotValue = 0;
    var hasMarginPosition = false;
    for (final entry in positions.entries) {
      final position = entry.value;
      if (position.netQuantity == 0) continue;
      final positionRule = _ruleFor(entry.key);
      final mark = markOverrides[entry.key] ?? _marks[entry.key]!;
      final signedMove = mark - position.averageEntryCents;
      final positionUnrealized = signedMove * position.netQuantity *
          positionRule.contractMultiplier;
      unrealized += positionUnrealized;
      if (positionRule.usesMargin) {
        hasMarginPosition = true;
        marginUnrealized += positionUnrealized;
        used += positionRule.initialMarginCents(
            priceCents: mark, quantity: position.netQuantity.abs());
        maintenance += positionRule.maintenanceMarginCents(
            priceCents: mark, quantity: position.netQuantity.abs());
      } else {
        spotValue += mark * position.netQuantity *
            positionRule.contractMultiplier;
      }
    }
    final equity = cash + spotValue + marginUnrealized;
    final free = hasMarginPosition ? equity - used : cash;
    final ratio = maintenance == 0 ? null : equity / maintenance;
    return TxMarketRiskSnapshot(
      cashCents: cash,
      equityCents: equity,
      unrealizedPnlCents: unrealized,
      realizedPnlCents: _realizedPnlCents,
      usedMarginCents: used,
      maintenanceMarginCents: maintenance,
      freeMarginCents: free,
      marginRatio: ratio,
      liquidationRequired: hasMarginPosition && maintenance > 0 && equity < maintenance,
      positions: Map.unmodifiable({
        for (final entry in positions.entries) entry.key: entry.value.freeze(),
      }),
    );
  }

  int _usedMargin({
    required Map<String, _MutablePosition> positions,
    required Map<String, int> markOverrides,
  }) {
    var total = 0;
    for (final entry in positions.entries) {
      final position = entry.value;
      if (position.netQuantity == 0) continue;
      final positionRule = _ruleFor(entry.key);
      if (!positionRule.usesMargin) continue;
      final mark = markOverrides[entry.key] ?? _marks[entry.key]!;
      total += positionRule.initialMarginCents(
          priceCents: mark, quantity: position.netQuantity.abs());
    }
    return total;
  }

  void _requireSymbol(String symbol) {
    if (!profile.instruments.any((item) => item.symbol == symbol)) {
      throw ArgumentError.value(symbol, 'symbol');
    }
  }

  TxMarketInstrument _instrument(String symbol) => profile.instruments
      .firstWhere((item) => item.symbol == symbol);

  TxMarketRiskRule _ruleFor(String symbol) {
    final instrument = _instrument(symbol);
    return TxMarketRiskRule(
      mode: rule.mode,
      usesMargin: instrument.usesMargin,
      supportsShort: instrument.supportsShort,
      tPlusOne: instrument.tPlusOne,
      initialMarginBps: rule.initialMarginBps,
      maintenanceMarginBps: rule.maintenanceMarginBps,
      shortBorrowBpsPerDay: rule.shortBorrowBpsPerDay,
      fundingBpsPerDay: rule.fundingBpsPerDay,
      rolloverBpsPerDay: rule.rolloverBpsPerDay,
      contractMultiplier: instrument.contractMultiplierUnits,
      lotSize: instrument.lotSize,
      tickSizeCents: rule.tickSizeCents,
      leverageLabel: rule.leverageLabel,
    );
  }

  static int _defaultMark(TxMarketMode mode, int index) => switch (mode) {
    TxMarketMode.aShare => index == 0 ? 1000 : 2500,
    TxMarketMode.usEquity => index == 0 ? 10000 : 25000,
    TxMarketMode.futures => index == 0 ? 30000 : 12000,
    TxMarketMode.crypto => index == 0 ? 5000000 : 300000,
    TxMarketMode.forex => index == 0 ? 10800 : 15000,
  };
}

class _MutablePosition {
  _MutablePosition({required this.symbol});

  _MutablePosition copy() => _MutablePosition(symbol: symbol)
    ..netQuantity = netQuantity
    ..averageEntryCents = averageEntryCents
    ..unsettledLongQuantity = unsettledLongQuantity
    ..realizedPnlCents = realizedPnlCents;

  final String symbol;
  int netQuantity = 0;
  int averageEntryCents = 0;
  int unsettledLongQuantity = 0;
  int realizedPnlCents = 0;

  int get availableToClose => netQuantity > 0
      ? netQuantity - unsettledLongQuantity
      : -netQuantity;

  TxMarketPosition freeze() => TxMarketPosition(
    symbol: symbol,
    netQuantity: netQuantity,
    averageEntryCents: averageEntryCents,
    unsettledLongQuantity: unsettledLongQuantity,
    realizedPnlCents: realizedPnlCents,
  );
}

class _PositionTransition {
  const _PositionTransition({
    required this.position,
    required this.closingQuantity,
    required this.openingQuantity,
    required this.realizedPnlCents,
  });

  final _MutablePosition position;
  final int closingQuantity;
  final int openingQuantity;
  final int realizedPnlCents;
}

class _CalculatedExecution {
  const _CalculatedExecution({
    required this.publicPlan,
    required this.newQuantity,
    required this.newAverageEntryCents,
    required this.newUnsettledLongQuantity,
    required this.closingQuantity,
    required this.openingQuantity,
    required this.realizedPnlCents,
    required this.feeCents,
    required this.projectedCashCents,
  });

  final TxMarketExecutionPlan publicPlan;
  final int newQuantity;
  final int newAverageEntryCents;
  final int newUnsettledLongQuantity;
  final int closingQuantity;
  final int openingQuantity;
  final int realizedPnlCents;
  final int feeCents;
  final int projectedCashCents;

  static _CalculatedExecution rejected({
    required TxSide side,
    required int quantity,
    required _MutablePosition current,
    int feeCents = 0,
  }) => _CalculatedExecution(
        publicPlan: TxMarketExecutionPlan(
          accepted: false,
          reason: null,
          side: side,
          requestedQuantity: quantity,
          closingQuantity: 0,
          openingQuantity: 0,
          realizedPnlCents: 0,
          feeCents: feeCents,
          projectedCashCents: 0,
          projectedUsedMarginCents: 0,
          projectedEquityCents: 0,
          projectedPosition: current.freeze(),
        ),
        newQuantity: current.netQuantity,
        newAverageEntryCents: current.averageEntryCents,
        newUnsettledLongQuantity: current.unsettledLongQuantity,
        closingQuantity: 0,
        openingQuantity: 0,
        realizedPnlCents: 0,
        feeCents: feeCents,
        projectedCashCents: 0,
      );

  _CalculatedExecution withReason(String reason) => _CalculatedExecution(
        publicPlan: TxMarketExecutionPlan(
          accepted: false,
          reason: reason,
          side: publicPlan.side,
          requestedQuantity: publicPlan.requestedQuantity,
          closingQuantity: closingQuantity,
          openingQuantity: openingQuantity,
          realizedPnlCents: realizedPnlCents,
          feeCents: feeCents,
          projectedCashCents: projectedCashCents,
          projectedUsedMarginCents: publicPlan.projectedUsedMarginCents,
          projectedEquityCents: publicPlan.projectedEquityCents,
          projectedPosition: publicPlan.projectedPosition,
        ),
        newQuantity: newQuantity,
        newAverageEntryCents: newAverageEntryCents,
        newUnsettledLongQuantity: newUnsettledLongQuantity,
        closingQuantity: closingQuantity,
        openingQuantity: openingQuantity,
        realizedPnlCents: realizedPnlCents,
        feeCents: feeCents,
        projectedCashCents: projectedCashCents,
      );

  static _CalculatedExecution accepted({
    required TxSide side,
    required int quantity,
    required _MutablePosition position,
    required int closingQuantity,
    required int openingQuantity,
    required int realizedPnlCents,
    required int feeCents,
    required int projectedCashCents,
    required int projectedUsedMarginCents,
    required int projectedEquityCents,
  }) => _CalculatedExecution(
        publicPlan: TxMarketExecutionPlan(
          accepted: true,
          reason: null,
          side: side,
          requestedQuantity: quantity,
          closingQuantity: closingQuantity,
          openingQuantity: openingQuantity,
          realizedPnlCents: realizedPnlCents,
          feeCents: feeCents,
          projectedCashCents: projectedCashCents,
          projectedUsedMarginCents: projectedUsedMarginCents,
          projectedEquityCents: projectedEquityCents,
          projectedPosition: position.freeze(),
        ),
        newQuantity: position.netQuantity,
        newAverageEntryCents: position.averageEntryCents,
        newUnsettledLongQuantity: position.unsettledLongQuantity,
        closingQuantity: closingQuantity,
        openingQuantity: openingQuantity,
        realizedPnlCents: realizedPnlCents,
        feeCents: feeCents,
        projectedCashCents: projectedCashCents,
      );
}
