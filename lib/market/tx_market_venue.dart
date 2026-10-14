import 'dart:convert';

import '../engine/tx_engine.dart';
import 'tx_market_profiles.dart';
import 'tx_market_risk_core.dart';
import 'tx_market_instruments.dart';

/// Deterministic taker/maker charges for the independent venue.
///
/// These are game rules, not external exchange rates. They are kept in the
/// venue so the account core receives the fee during the same atomic fork as
/// the fill; a displayed quote can never silently charge an account.
class TxMarketFeePolicy {
  const TxMarketFeePolicy({required this.mode, required this.makerBps,
    required this.takerBps});

  final TxMarketMode mode;
  final int makerBps;
  final int takerBps;

  static const usEquity = TxMarketFeePolicy(
      mode: TxMarketMode.usEquity, makerBps: 1, takerBps: 5);
  static const futures = TxMarketFeePolicy(
      mode: TxMarketMode.futures, makerBps: 1, takerBps: 2);
  static const crypto = TxMarketFeePolicy(
      mode: TxMarketMode.crypto, makerBps: 2, takerBps: 5);
  static const forex = TxMarketFeePolicy(
      mode: TxMarketMode.forex, makerBps: 1, takerBps: 3);

  static TxMarketFeePolicy forMode(TxMarketMode mode) => switch (mode) {
    TxMarketMode.aShare => throw ArgumentError('A股使用已连接费用规则'),
    TxMarketMode.usEquity => usEquity,
    TxMarketMode.futures => futures,
    TxMarketMode.crypto => crypto,
    TxMarketMode.forex => forex,
  };

  int feeCents({required TxMarketProfile profile, required String symbol,
      required int quantity, required int priceCents, required bool maker}) {
    final instrument = profile.instruments.firstWhere(
        (item) => item.symbol == symbol);
    final bps = maker ? makerBps : takerBps;
    final notional = priceCents * quantity * instrument.contractMultiplierUnits;
    return (notional * bps + 9999) ~/ 10000;
  }
}

/// One fill from the independent multi-market venue. It is only created after
/// both account cores accept the same price/quantity transition.
class TxMarketVenueFill {
  const TxMarketVenueFill({
    required this.id,
    required this.symbol,
    required this.buyOrderId,
    required this.sellOrderId,
    required this.quantity,
    required this.priceCents,
    this.gameDay = 1,
    this.minuteOfDay = 0,
    this.contractMultiplierUnits = 1,
    this.makerFeeCents = 0,
    this.takerFeeCents = 0,
  });

  final String id;
  final String symbol;
  final String buyOrderId;
  final String sellOrderId;
  final int quantity;
  final int priceCents;
  /// Game-time location of the print. Keeping the timestamp on the fill lets
  /// an independent market rebuild trade-only OHLCV after a restart without
  /// inventing bars from marks or resting quotes.
  final int gameDay;
  final int minuteOfDay;
  final int contractMultiplierUnits;
  final int makerFeeCents;
  final int takerFeeCents;

  int get notionalCents =>
      quantity * priceCents * contractMultiplierUnits;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'symbol': symbol,
        'buyOrderId': buyOrderId,
        'sellOrderId': sellOrderId,
        'quantity': quantity,
        'priceCents': priceCents,
        'gameDay': gameDay,
        'minuteOfDay': minuteOfDay,
        'contractMultiplierUnits': contractMultiplierUnits,
        'makerFeeCents': makerFeeCents,
        'takerFeeCents': takerFeeCents,
      };

  static TxMarketVenueFill fromJson(Map<String, dynamic> data) {
    if (data['id'] is! String || data['symbol'] is! String ||
        data['buyOrderId'] is! String || data['sellOrderId'] is! String ||
        data['quantity'] is! int || data['priceCents'] is! int ||
        data['contractMultiplierUnits'] is! int ||
        data['makerFeeCents'] is! int || data['takerFeeCents'] is! int) {
      throw const FormatException('Invalid venue fill');
    }
    final makerFee = data['makerFeeCents'];
    final takerFee = data['takerFeeCents'];
    final multiplier = data['contractMultiplierUnits'];
    // Venue schema 2 snapshots did not carry print timestamps. Treat those
    // legacy fills as day 1/minute 0; they remain auditable and new fills are
    // fully timestamped by the current venue.
    final gameDay = data['gameDay'] ?? 1;
    final minuteOfDay = data['minuteOfDay'] ?? 0;
    if (multiplier is! int || multiplier < 1 || makerFee is! int ||
        takerFee is! int || makerFee < 0 || takerFee < 0 ||
        gameDay is! int || gameDay < 1 || minuteOfDay is! int ||
        minuteOfDay < 0 || minuteOfDay >= 1440) {
      throw const FormatException('Invalid venue fill fee');
    }
    return TxMarketVenueFill(
      id: data['id'] as String,
      symbol: data['symbol'] as String,
      buyOrderId: data['buyOrderId'] as String,
      sellOrderId: data['sellOrderId'] as String,
      quantity: data['quantity'] as int,
      priceCents: data['priceCents'] as int,
      gameDay: gameDay,
      minuteOfDay: minuteOfDay,
      contractMultiplierUnits: multiplier as int,
      makerFeeCents: makerFee as int,
      takerFeeCents: takerFee as int,
    );
  }
}

/// Atomic settlement result for every account in one independent venue.
///
/// A venue owns several independent account cores, so advancing only one core
/// would make the shared market appear to have different dates, marks or
/// financing rules. The venue therefore publishes one immutable batch after
/// every account has passed the same settlement preflight.
class TxMarketVenueSettlement {
  TxMarketVenueSettlement({
    required this.mode,
    required this.fromGameDay,
    required this.toGameDay,
    required Map<String, TxMarketSettlement> settlements,
  })  : settlements = Map.unmodifiable(Map<String, TxMarketSettlement>.from(
          settlements)),
        riskSnapshots = Map.unmodifiable({
          for (final entry in settlements.entries) entry.key: entry.value.risk,
        });

  final TxMarketMode mode;
  final int fromGameDay;
  final int toGameDay;
  final Map<String, TxMarketSettlement> settlements;
  final Map<String, TxMarketRiskSnapshot> riskSnapshots;

  List<String> get liquidationRequiredAccounts => List.unmodifiable([
        for (final entry in riskSnapshots.entries)
          if (entry.value.liquidationRequired) entry.key,
      ]);
}

/// Read-only execution preview derived from the current resting book.
///
/// A preview never allocates an order id, consumes a level or changes an
/// account balance. The venue forks the same risk cores used by real fills so
/// margin, short and reduce-only gates are represented honestly.
class TxMarketExecutionPreview {
  const TxMarketExecutionPreview({
    required this.accepted,
    required this.reason,
    required this.side,
    required this.kind,
    required this.requestedQuantity,
    required this.executableQuantity,
    required this.remainingQuantity,
    required this.notionalCents,
    required this.takerFeeCents,
    required this.makerFeeCents,
    required this.bestPriceCents,
    required this.worstPriceCents,
    required this.levelsConsumed,
  });

  final bool accepted;
  final String? reason;
  final TxSide side;
  final TxKind kind;
  final int requestedQuantity;
  final int executableQuantity;
  final int remainingQuantity;
  final int notionalCents;
  final int takerFeeCents;
  final int makerFeeCents;
  final int? bestPriceCents;
  final int? worstPriceCents;
  final int levelsConsumed;

  bool get fullyExecutable => accepted && remainingQuantity == 0;
  double? get vwapCents => executableQuantity == 0
      ? null : notionalCents / executableQuantity;
  double? get priceImpactBasisPoints {
    if (bestPriceCents == null || worstPriceCents == null ||
        bestPriceCents == 0) return null;
    return (worstPriceCents! - bestPriceCents!).abs() * 10000.0 /
        bestPriceCents!;
  }
}

/// One real reduce-only order emitted by venue-level liquidation.
class TxMarketLiquidationLeg {
  const TxMarketLiquidationLeg({
    required this.symbol,
    required this.requestedQuantity,
    required this.order,
  });

  final String symbol;
  final int requestedQuantity;
  final TxMarketVenueOrder order;

  int get filledQuantity => order.filled;
  int get unfilledQuantity => order.remaining;
}

/// Venue-level liquidation report. Unfilled quantity is evidence that the
/// book did not contain enough real opposite liquidity.
class TxMarketLiquidationReport {
  const TxMarketLiquidationReport({
    required this.ownerId,
    required this.triggered,
    required this.legs,
    required this.risk,
  });

  final String ownerId;
  final bool triggered;
  final List<TxMarketLiquidationLeg> legs;
  final TxMarketRiskSnapshot risk;

  int get requestedQuantity =>
      legs.fold(0, (sum, leg) => sum + leg.requestedQuantity);
  int get filledQuantity =>
      legs.fold(0, (sum, leg) => sum + leg.filledQuantity);
  int get unfilledQuantity =>
      legs.fold(0, (sum, leg) => sum + leg.unfilledQuantity);
}

/// Low-cost venue telemetry for the UI and long-run soak diagnostics. Depth
/// counters are process-local observations and are not part of an economic
/// snapshot.
class TxMarketVenueStats {
  const TxMarketVenueStats({
    required this.totalOrders,
    required this.activeOrders,
    required this.fillCount,
    required this.bookRevision,
    required this.depthQueries,
    required this.depthCacheHits,
  });

  final int totalOrders;
  final int activeOrders;
  final int fillCount;
  final int bookRevision;
  final int depthQueries;
  final int depthCacheHits;

  double get depthCacheHitRate => depthQueries == 0
      ? 0.0 : depthCacheHits / depthQueries;
}

/// Immutable order view for the independent venue. Unlike the connected
/// A-share engine, this venue deliberately has no reservation ledger yet;
/// risk is checked atomically at each actual fill.
class TxMarketVenueOrder {
  const TxMarketVenueOrder({
    required this.id,
    required this.ownerId,
    required this.symbol,
    required this.side,
    required this.kind,
    required this.timeInForce,
    required this.quantity,
    required this.remaining,
    required this.limitPriceCents,
    required this.sequence,
    required this.status,
    required this.reduceOnly,
    required this.rejectReason,
  });

  final String id;
  final String ownerId;
  final String symbol;
  final TxSide side;
  final TxKind kind;
  final TxTimeInForce timeInForce;
  final int quantity;
  final int remaining;
  final int? limitPriceCents;
  final int sequence;
  final TxStatus status;
  final bool reduceOnly;
  final String? rejectReason;

  int get filled => quantity - remaining;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'ownerId': ownerId,
        'symbol': symbol,
        'side': side.name,
        'kind': kind.name,
        'timeInForce': timeInForce.name,
        'quantity': quantity,
        'remaining': remaining,
        'limitPriceCents': limitPriceCents,
        'sequence': sequence,
        'status': status.name,
        'reduceOnly': reduceOnly,
        'rejectReason': rejectReason,
      };
}

/// Deterministic price-time venue for the four independent market modes.
///
/// The venue matches synthetic participants against real account/risk cores.
/// It has no network price feed or hidden infinite liquidity. Deterministic
/// maker/taker fees are applied inside the same account fork as each fill. An
/// unmatched GTC remainder rests visibly; IOC/market remainders cancel and
/// FOK rejects atomically. Account updates are committed only after every
/// simulated leg passes its own risk gate.
class TxMarketVenue {
  static const snapshotSchema = 3;

  TxMarketVenue({
    required this.profile,
    required Map<String, TxMarketCore> accounts,
  }) : _accounts = Map<String, TxMarketCore>.from(accounts),
       feePolicy = TxMarketFeePolicy.forMode(profile.mode) {
    if (_accounts.isEmpty) throw ArgumentError('Venue needs one account');
    if (profile.mode == TxMarketMode.aShare) {
      throw ArgumentError('A股继续使用已连接现货核心，不接入独立 venue');
    }
    for (final account in _accounts.values) {
      if (account.profile.mode != profile.mode) {
        throw ArgumentError('All venue accounts must use the same market mode');
      }
    }
  }

  final TxMarketProfile profile;
  final TxMarketFeePolicy feePolicy;
  final Map<String, TxMarketCore> _accounts;
  final Map<String, _VenueOrder> _orders = {};
  final List<TxMarketVenueFill> _fills = [];
  final Map<String, List<TxBookLevel>> _depthCache = {};
  int _nextSequence = 1;
  int _nextFill = 1;
  int _bookRevision = 0;
  int _depthCacheRevision = 0;
  int _depthQueries = 0;
  int _depthCacheHits = 0;

  TxMarketCore account(String ownerId) {
    final account = _accounts[ownerId];
    if (account == null) throw ArgumentError.value(ownerId, 'ownerId');
    return account;
  }

  Map<String, TxMarketCore> get accounts => Map.unmodifiable(_accounts);
  List<TxMarketVenueFill> get fills => List.unmodifiable(_fills);

  /// Current account risk views, all sourced from the same venue-owned cores.
  /// This is a read-only projection and never advances a mark or game day.
  Map<String, TxMarketRiskSnapshot> get riskSnapshots => Map.unmodifiable({
        for (final entry in _accounts.entries) entry.key: entry.value.snapshot(),
      });

  TxMarketVenueStats get stats => TxMarketVenueStats(
        totalOrders: _orders.length,
        activeOrders: activeOrders.length,
        fillCount: _fills.length,
        bookRevision: _bookRevision,
        depthQueries: _depthQueries,
        depthCacheHits: _depthCacheHits,
      );

  /// Broadcast one validated market mark through every account atomically.
  ///
  /// The independent venue has no external price feed; callers must provide
  /// the game's already-validated synthetic mark. Forking every account first
  /// prevents one participant from receiving a mark when another participant
  /// rejects the same update.
  Map<String, TxMarketRiskSnapshot> markToMarket({
    required String symbol,
    required int priceCents,
  }) {
    _instrument(symbol);
    TxMarketRiskRules.forMode(profile.mode).validatePrice(priceCents);
    final forks = <String, TxMarketCore>{};
    for (final entry in _accounts.entries) {
      final fork = entry.value.fork()
        ..markToMarket(symbol: symbol, priceCents: priceCents);
      forks[entry.key] = fork;
    }
    for (final entry in forks.entries) {
      _accounts[entry.key]!.commitFork(entry.value);
    }
    checkInvariants();
    return riskSnapshots;
  }

  /// Advance every account through one explicit daily settlement atomically.
  ///
  /// The result exposes mark-to-market, borrow/funding/rollover cash effects
  /// and post-settlement liquidation warnings. It does not invent a
  /// liquidation fill or infinite liquidity; a later venue order or explicit
  /// risk action must perform that trade against real depth.
  TxMarketVenueSettlement settleDay({required int nextGameDay}) {
    if (_accounts.values.any((account) => account.gameDay != _accounts.values
        .first.gameDay)) {
      throw StateError('Venue account game days are inconsistent');
    }
    final fromGameDay = _accounts.values.first.gameDay;
    if (nextGameDay <= fromGameDay) {
      throw ArgumentError.value(nextGameDay, 'nextGameDay',
          'Settlement must advance the venue game day');
    }
    final forks = <String, TxMarketCore>{};
    final settlements = <String, TxMarketSettlement>{};
    for (final entry in _accounts.entries) {
      final fork = entry.value.fork();
      settlements[entry.key] = fork.settleDay(nextGameDay: nextGameDay);
      forks[entry.key] = fork;
    }
    for (final entry in forks.entries) {
      _accounts[entry.key]!.commitFork(entry.value);
    }
    checkInvariants();
    return TxMarketVenueSettlement(
      mode: profile.mode,
      fromGameDay: fromGameDay,
      toGameDay: nextGameDay,
      settlements: settlements,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': snapshotSchema,
        'mode': profile.mode.name,
        'nextSequence': _nextSequence,
        'nextFill': _nextFill,
        'accounts': <String, dynamic>{
          for (final entry in _accounts.entries) entry.key: entry.value.toJson(),
        },
        'orders': [for (final order in _orders.values) order.freeze().toJson()],
        'fills': [for (final fill in _fills) fill.toJson()],
      };

  String exportJson() => jsonEncode(toJson());

  static TxMarketVenue fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid venue JSON');
    return fromJsonMap(Map<String, dynamic>.from(decoded));
  }

  static TxMarketVenue fromJsonMap(Map<String, dynamic> data) {
    if ((data['schema'] != 2 && data['schema'] != snapshotSchema) ||
        data['mode'] is! String ||
        data['accounts'] is! Map || data['orders'] is! List ||
        data['fills'] is! List || data['nextSequence'] is! int ||
        data['nextFill'] is! int) {
      throw const FormatException('Invalid venue snapshot');
    }
    final mode = TxMarketMode.values.firstWhere(
        (value) => value.name == data['mode'],
        orElse: () => throw const FormatException('Unknown venue mode'));
    final profile = TxMarketProfile.of(mode);
    final accounts = <String, TxMarketCore>{};
    for (final entry in (data['accounts'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid venue account');
      }
      accounts[entry.key as String] = TxMarketCore.fromJsonMap(
          Map<String, dynamic>.from(entry.value as Map));
    }
    final venue = TxMarketVenue(profile: profile, accounts: accounts)
      .._nextSequence = data['nextSequence'] as int
      .._nextFill = data['nextFill'] as int;
    if (venue._nextSequence < 1 || venue._nextFill < 1) {
      throw const FormatException('Invalid venue sequence');
    }
    final orderIds = <String>{};
    for (final rawOrder in data['orders'] as List) {
      if (rawOrder is! Map) throw const FormatException('Invalid venue order');
      final source = Map<String, dynamic>.from(rawOrder);
      if (source['id'] is! String || source['ownerId'] is! String ||
          source['symbol'] is! String || source['side'] is! String ||
          source['kind'] is! String || source['timeInForce'] is! String ||
          source['quantity'] is! int || source['remaining'] is! int ||
          source['sequence'] is! int || source['status'] is! String ||
          source['reduceOnly'] is! bool) {
        throw const FormatException('Invalid venue order fields');
      }
      final id = source['id'] as String;
      if (!orderIds.add(id)) throw const FormatException('Duplicate venue order');
      final side = TxSide.values.firstWhere(
          (value) => value.name == source['side'],
          orElse: () => throw const FormatException('Unknown venue side'));
      final kind = TxKind.values.firstWhere(
          (value) => value.name == source['kind'],
          orElse: () => throw const FormatException('Unknown venue kind'));
      final tif = TxTimeInForce.values.firstWhere(
          (value) => value.name == source['timeInForce'],
          orElse: () => throw const FormatException('Unknown venue TIF'));
      final status = TxStatus.values.firstWhere(
          (value) => value.name == source['status'],
          orElse: () => throw const FormatException('Unknown venue status'));
      final order = _VenueOrder(
        id: id,
        ownerId: source['ownerId'] as String,
        symbol: source['symbol'] as String,
        side: side,
        kind: kind,
        quantity: source['quantity'] as int,
        limitPriceCents: source['limitPriceCents'] as int?,
        timeInForce: tif,
        sequence: source['sequence'] as int,
        reduceOnly: source['reduceOnly'] as bool,
      )
        ..remaining = source['remaining'] as int
        ..status = status
        ..rejectReason = source['rejectReason'] as String?;
      venue._orders[id] = order;
    }
    final fillIds = <String>{};
    for (final rawFill in data['fills'] as List) {
      if (rawFill is! Map) throw const FormatException('Invalid venue fill row');
      final fill = TxMarketVenueFill.fromJson(
          Map<String, dynamic>.from(rawFill));
      if (!fillIds.add(fill.id)) throw const FormatException('Duplicate venue fill');
      venue._fills.add(fill);
    }
    venue.checkInvariants();
    return venue;
  }

  Iterable<TxMarketVenueOrder> get activeOrders sync* {
    for (final order in _orders.values) {
      if (order.remaining > 0 &&
          (order.status == TxStatus.open ||
              order.status == TxStatus.partiallyFilled)) {
        yield order.freeze();
      }
    }
  }

  /// Complete immutable order history for account/record views. The venue
  /// keeps this separate from [activeOrders] so a filled, cancelled or
  /// rejected order remains auditable after it leaves the visible book.
  List<TxMarketVenueOrder> get orders => List.unmodifiable([
        for (final order in _orders.values) order.freeze(),
      ]);

  TxMarketVenueOrder order(String id) {
    final result = _orders[id];
    if (result == null) throw ArgumentError.value(id, 'id');
    return result.freeze();
  }

  /// Preview the same price-time path used by [place], without publishing a
  /// candidate order or changing any account.
  TxMarketExecutionPreview previewOrder({
    required String ownerId,
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
    account(ownerId);
    _validateOrderRequest(symbol, kind, quantity, limitPriceCents,
        timeInForce);
    final status = profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    if (!status.isOpen) {
      return _previewFailure(
        side: side, kind: kind, quantity: quantity,
        reason: '${status.label}，当前不可成交',
      );
    }
    final candidate = _VenueOrder(
      id: 'preview',
      ownerId: ownerId,
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
      timeInForce: timeInForce,
      sequence: _nextSequence,
      reduceOnly: reduceOnly,
    );
    final makers = _eligibleMakers(candidate);
    if (timeInForce == TxTimeInForce.postOnly && makers.isNotEmpty) {
      return _previewFailure(
        side: side, kind: kind, quantity: quantity,
        reason: 'Post-only 委托会吃掉现有流动性',
      );
    }
    final simulation = _simulate(candidate, makers,
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    if (simulation.reason != null) {
      return _previewFailure(
        side: side, kind: kind, quantity: quantity,
        reason: simulation.reason!,
      );
    }
    if (timeInForce == TxTimeInForce.fok && simulation.remaining != 0) {
      return _previewFailure(
        side: side, kind: kind, quantity: quantity,
        reason: 'FOK 可成交深度不足，未产生任何成交',
      );
    }
    final instrument = _instrument(symbol);
    var notional = 0;
    var takerFee = 0;
    var makerFee = 0;
    int? best;
    int? worst;
    final consumedPrices = <int>{};
    for (final trade in simulation.trades) {
      notional += trade.quantity * trade.priceCents *
          instrument.contractMultiplierUnits;
      takerFee += trade.takerFeeCents;
      makerFee += trade.makerFeeCents;
      best ??= trade.priceCents;
      worst = trade.priceCents;
      consumedPrices.add(trade.priceCents);
    }
    return TxMarketExecutionPreview(
      accepted: true,
      reason: null,
      side: side,
      kind: kind,
      requestedQuantity: quantity,
      executableQuantity: quantity - simulation.remaining,
      remainingQuantity: simulation.remaining,
      notionalCents: notional,
      takerFeeCents: takerFee,
      makerFeeCents: makerFee,
      bestPriceCents: best,
      worstPriceCents: worst,
      levelsConsumed: consumedPrices.length,
    );
  }

  TxMarketExecutionPreview _previewFailure({
    required TxSide side,
    required TxKind kind,
    required int quantity,
    required String reason,
  }) => TxMarketExecutionPreview(
        accepted: false,
        reason: reason,
        side: side,
        kind: kind,
        requestedQuantity: quantity,
        executableQuantity: 0,
        remainingQuantity: quantity,
        notionalCents: 0,
        takerFeeCents: 0,
        makerFeeCents: 0,
        bestPriceCents: null,
        worstPriceCents: null,
        levelsConsumed: 0,
      );

  /// Close a margin-breached account only through actual opposite-side book
  /// liquidity. Each leg is a normal venue market order with reduce-only
  /// enabled. A missing bid/ask leaves a visible remainder in the report.
  TxMarketLiquidationReport liquidateAccountAgainstBook({
    required String ownerId,
    required int gameDay,
    required int minuteOfDay,
    String orderIdPrefix = 'LIQ',
  }) {
    final accountCore = account(ownerId);
    final before = accountCore.snapshot();
    if (!before.liquidationRequired) {
      return TxMarketLiquidationReport(
        ownerId: ownerId,
        triggered: false,
        legs: const [],
        risk: before,
      );
    }
    final positions = before.positions.values
        .where((position) => !position.isFlat)
        .toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
    final legs = <TxMarketLiquidationLeg>[];
    var index = 0;
    for (final position in positions) {
      final quantity = position.netQuantity.abs();
      if (quantity == 0) continue;
      final order = place(
        id: '$orderIdPrefix-$ownerId-${index++}',
        ownerId: ownerId,
        symbol: position.symbol,
        side: position.netQuantity > 0 ? TxSide.sell : TxSide.buy,
        kind: TxKind.market,
        quantity: quantity,
        limitPriceCents: null,
        timeInForce: TxTimeInForce.gtc,
        gameDay: gameDay,
        minuteOfDay: minuteOfDay,
        reduceOnly: true,
      );
      legs.add(TxMarketLiquidationLeg(
        symbol: position.symbol,
        requestedQuantity: quantity,
        order: order,
      ));
    }
    return TxMarketLiquidationReport(
      ownerId: ownerId,
      triggered: true,
      legs: List.unmodifiable(legs),
      risk: accountCore.snapshot(),
    );
  }

  TxMarketVenueOrder place({
    required String id,
    required String ownerId,
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
    final existing = _orders[id];
    if (existing != null) {
      if (!existing.sameRequest(ownerId, symbol, side, kind, quantity,
          limitPriceCents, timeInForce, reduceOnly)) {
        throw StateError('Conflicting venue retry: $id');
      }
      return existing.freeze();
    }
    account(ownerId);
    _validateOrderRequest(symbol, kind, quantity, limitPriceCents,
        timeInForce);
    final status = profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    final candidate = _VenueOrder(
      id: id,
      ownerId: ownerId,
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
      timeInForce: timeInForce,
      sequence: _nextSequence++,
      reduceOnly: reduceOnly,
    );
    _orders[id] = candidate;
    _touchBook();

    if (!status.isOpen) {
      return _reject(candidate, '${status.label}，当前不可成交');
    }

    final makers = _eligibleMakers(candidate);
    if (timeInForce == TxTimeInForce.postOnly && makers.isNotEmpty) {
      return _reject(candidate, 'Post-only 委托会吃掉现有流动性');
    }
    final simulation = _simulate(candidate, makers,
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    if (simulation.reason != null) {
      return _reject(candidate, simulation.reason!);
    }
    if (timeInForce == TxTimeInForce.fok &&
        simulation.remaining != 0) {
      return _reject(candidate, 'FOK 可成交深度不足，未产生任何成交');
    }

    for (final entry in simulation.forks.entries) {
      _accounts[entry.key]!.commitFork(entry.value);
    }
    for (final trade in simulation.trades) {
      final maker = _orders[trade.maker.id]!;
      maker.remaining -= trade.quantity;
      _refresh(maker);
      final fill = TxMarketVenueFill(
        id: 'V-F-${_nextFill++}',
        symbol: candidate.symbol,
        buyOrderId: candidate.side == TxSide.buy ? candidate.id : maker.id,
        sellOrderId: candidate.side == TxSide.sell ? candidate.id : maker.id,
        quantity: trade.quantity,
        priceCents: trade.priceCents,
        gameDay: gameDay,
        minuteOfDay: minuteOfDay,
        contractMultiplierUnits: profile.instruments
            .firstWhere((item) => item.symbol == candidate.symbol)
            .contractMultiplierUnits,
        makerFeeCents: trade.makerFeeCents,
        takerFeeCents: trade.takerFeeCents,
      );
      _fills.add(fill);
    }
    candidate.remaining = simulation.remaining;
    // A market order may sweep several levels, but its remainder can never
    // become a resting book order even when the caller supplies venue-default
    // GTC.
    if (candidate.remaining > 0 && candidate.kind == TxKind.limit &&
        candidate.timeInForce.canRest) {
      candidate.status = candidate.filled == 0
          ? TxStatus.open : TxStatus.partiallyFilled;
    } else if (candidate.remaining > 0) {
      candidate.status = TxStatus.cancelled;
    } else {
      candidate.status = TxStatus.filled;
    }
    _touchBook();
    checkInvariants();
    return candidate.freeze();
  }

  TxMarketVenueOrder cancel(String id, {required String ownerId}) {
    final target = _orders[id];
    if (target == null) throw ArgumentError.value(id, 'id');
    if (target.ownerId != ownerId) throw StateError('Order owner mismatch');
    if (target.remaining == 0 ||
        (target.status != TxStatus.open &&
            target.status != TxStatus.partiallyFilled)) {
      return target.freeze();
    }
    target.status = TxStatus.cancelled;
    _touchBook();
    checkInvariants();
    return target.freeze();
  }

  List<TxBookLevel> depth(String symbol, TxSide side, {int levels = 5}) {
    if (levels < 0) throw ArgumentError.value(levels, 'levels');
    _depthQueries++;
    if (_depthCacheRevision != _bookRevision) {
      _depthCache.clear();
      _depthCacheRevision = _bookRevision;
    }
    final cacheKey = '$symbol|${side.name}|$levels';
    final cached = _depthCache[cacheKey];
    if (cached != null) {
      _depthCacheHits++;
      return cached;
    }
    final byPrice = <int, List<int>>{};
    for (final order in _orders.values) {
      if (order.symbol != symbol || order.side != side ||
          order.remaining <= 0 ||
          (order.status != TxStatus.open &&
              order.status != TxStatus.partiallyFilled)) continue;
      final cell = byPrice.putIfAbsent(order.limitPriceCents!, () => [0, 0]);
      cell[0] += order.remaining;
      cell[1]++;
    }
    final prices = byPrice.keys.toList()..sort();
    if (side == TxSide.buy) prices.sort((a, b) => b.compareTo(a));
    final result = List<TxBookLevel>.unmodifiable(prices.take(levels).map(
        (price) => TxBookLevel(
            price, byPrice[price]![0], byPrice[price]![1])).toList());
    _depthCache[cacheKey] = result;
    return result;
  }

  void checkInvariants() {
    var expectedSequence = 1;
    final filledByOrder = <String, int>{};
    final fillIds = <String>{};
    final risk = TxMarketRiskRules.forMode(profile.mode);
    for (final order in _orders.values) {
      if (order.sequence != expectedSequence++ || order.quantity < 1 ||
          order.remaining < 0 || order.remaining > order.quantity) {
        throw StateError('Invalid venue order sequence or quantity');
      }
      if (!_accounts.containsKey(order.ownerId) ||
          !profile.instruments.any((item) => item.symbol == order.symbol)) {
        throw StateError('Venue order references unknown account or symbol');
      }
      if (order.id.isEmpty || order.ownerId.isEmpty) {
        throw StateError('Venue order has an empty identity');
      }
      if (order.kind == TxKind.market &&
          (order.limitPriceCents != null ||
              order.timeInForce != TxTimeInForce.gtc)) {
        throw StateError('Invalid market order projection');
      }
      if (order.kind == TxKind.limit) {
        final price = order.limitPriceCents;
        if (price == null) throw StateError('Limit order has no price');
        try {
          risk.validatePrice(price);
        } on ArgumentError {
          throw StateError('Venue order has an invalid limit price');
        }
      }
      final active = order.remaining > 0 &&
          (order.status == TxStatus.open ||
              order.status == TxStatus.partiallyFilled);
      if (active && (order.kind != TxKind.limit ||
          order.limitPriceCents == null || !order.timeInForce.canRest)) {
        throw StateError('Invalid active venue order');
      }
      switch (order.status) {
        case TxStatus.open:
          if (order.remaining <= 0 || order.filled != 0) {
            throw StateError('Open venue order has an invalid fill state');
          }
        case TxStatus.partiallyFilled:
          if (order.remaining <= 0 || order.filled <= 0) {
            throw StateError('Partial venue order has an invalid fill state');
          }
        case TxStatus.filled:
          if (order.remaining != 0) {
            throw StateError('Filled venue order still has remainder');
          }
        case TxStatus.cancelled:
          if (order.remaining <= 0) {
            throw StateError('Cancelled venue order has no remainder');
          }
        case TxStatus.rejected:
          if (order.filled != 0 || order.remaining != order.quantity) {
            throw StateError('Rejected venue order has an invalid fill state');
          }
      }
    }
    if (_nextSequence != expectedSequence) {
      throw StateError('Venue sequence cursor is inconsistent');
    }
    for (final fill in _fills) {
      if (fill.quantity < 1 || fill.priceCents < 1 ||
          fill.makerFeeCents < 0 || fill.takerFeeCents < 0 ||
          !_orders.containsKey(fill.buyOrderId) ||
          !_orders.containsKey(fill.sellOrderId) ||
          !profile.instruments.any((item) => item.symbol == fill.symbol)) {
        throw StateError('Invalid venue fill');
      }
      if (fill.id.isEmpty || !fillIds.add(fill.id)) {
        throw StateError('Duplicate venue fill id');
      }
      final instrument = profile.instruments
          .firstWhere((item) => item.symbol == fill.symbol);
      if (fill.contractMultiplierUnits != instrument.contractMultiplierUnits) {
        throw StateError('Venue fill multiplier mismatch');
      }
      if (fill.gameDay < 1 || fill.minuteOfDay < 0 ||
          fill.minuteOfDay >= 1440) {
        throw StateError('Venue fill has an invalid game timestamp');
      }
      if (fill.quantity % instrument.lotSize != 0) {
        throw StateError('Venue fill quantity violates lot size');
      }
      try {
        risk.validatePrice(fill.priceCents);
      } on ArgumentError {
        throw StateError('Venue fill has an invalid price');
      }
      final buy = _orders[fill.buyOrderId]!;
      final sell = _orders[fill.sellOrderId]!;
      if (buy.side != TxSide.buy || sell.side != TxSide.sell ||
          buy.symbol != fill.symbol || sell.symbol != fill.symbol) {
        throw StateError('Venue fill side or symbol mismatch');
      }
      filledByOrder[fill.buyOrderId] =
          (filledByOrder[fill.buyOrderId] ?? 0) + fill.quantity;
      filledByOrder[fill.sellOrderId] =
          (filledByOrder[fill.sellOrderId] ?? 0) + fill.quantity;
    }
    for (final order in _orders.values) {
      if ((filledByOrder[order.id] ?? 0) != order.filled) {
        throw StateError('Venue fill quantity does not match order');
      }
    }
    if (_nextFill != _fills.length + 1) {
      throw StateError('Venue fill cursor is inconsistent');
    }
  }

  void _validateOrderRequest(String symbol, TxKind kind,
      int quantity, int? price, TxTimeInForce timeInForce) {
    final instrument = profile.instruments.firstWhere(
        (item) => item.symbol == symbol,
        orElse: () => throw ArgumentError.value(symbol, 'symbol'));
    final risk = TxMarketRiskRules.forMode(profile.mode);
    if (quantity < 1 || quantity > TxEngine.maxQuantity ||
        quantity % instrument.lotSize != 0) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    if (kind == TxKind.market &&
        (price != null || timeInForce != TxTimeInForce.gtc)) {
      throw ArgumentError('Market order must use GTC and no limit price');
    }
    if (kind == TxKind.limit) {
      if (price == null) throw ArgumentError('Limit order needs a price');
      risk.validatePrice(price);
    }
    if (instrument.symbol.isEmpty) throw StateError('Invalid instrument');
  }

  TxMarketInstrument _instrument(String symbol) => profile.instruments
      .firstWhere((item) => item.symbol == symbol,
          orElse: () => throw ArgumentError.value(symbol, 'symbol'));

  List<_VenueOrder> _eligibleMakers(_VenueOrder taker) {
    final makers = <_VenueOrder>[];
    for (final order in _orders.values) {
      if (order.id == taker.id || order.symbol != taker.symbol ||
          order.side == taker.side || order.remaining <= 0 ||
          (order.status != TxStatus.open &&
              order.status != TxStatus.partiallyFilled)) continue;
      final crosses = taker.kind == TxKind.market ||
          (taker.side == TxSide.buy
              ? taker.limitPriceCents! >= order.limitPriceCents!
              : taker.limitPriceCents! <= order.limitPriceCents!);
      if (crosses) makers.add(order);
    }
    makers.sort((a, b) {
      final price = taker.side == TxSide.buy
          ? a.limitPriceCents!.compareTo(b.limitPriceCents!)
          : b.limitPriceCents!.compareTo(a.limitPriceCents!);
      return price == 0
          ? a.sequence.compareTo(b.sequence) : price;
    });
    return makers;
  }

  _VenueSimulation _simulate(_VenueOrder taker, List<_VenueOrder> makers,
      {required int gameDay, required int minuteOfDay}) {
    final forks = <String, TxMarketCore>{};
    final trades = <_VenueTrade>[];
    var remaining = taker.quantity;
    for (final maker in makers) {
      if (remaining == 0) break;
      if (maker.ownerId == taker.ownerId) {
        return _VenueSimulation.reason('禁止自成交：${maker.id}');
      }
      final quantity = remaining < maker.remaining
          ? remaining : maker.remaining;
      final price = maker.limitPriceCents!;
      final takerFee = feePolicy.feeCents(
        profile: profile,
        symbol: taker.symbol,
        quantity: quantity,
        priceCents: price,
        maker: false,
      );
      final makerFee = feePolicy.feeCents(
        profile: profile,
        symbol: maker.symbol,
        quantity: quantity,
        priceCents: price,
        maker: true,
      );
      final takerCore = forks.putIfAbsent(
          taker.ownerId, () => account(taker.ownerId).fork());
      final makerCore = forks.putIfAbsent(
          maker.ownerId, () => account(maker.ownerId).fork());
      try {
        takerCore.applyExecution(
          symbol: taker.symbol,
          side: taker.side,
          quantity: quantity,
          priceCents: price,
          gameDay: gameDay,
          minuteOfDay: minuteOfDay,
          reduceOnly: taker.reduceOnly,
          feeCents: takerFee,
        );
        makerCore.applyExecution(
          symbol: maker.symbol,
          side: maker.side,
          quantity: quantity,
          priceCents: price,
          gameDay: gameDay,
          minuteOfDay: minuteOfDay,
          reduceOnly: maker.reduceOnly,
          feeCents: makerFee,
        );
      } on StateError catch (error) {
        return _VenueSimulation.reason(error.message);
      }
      trades.add(_VenueTrade(
        maker: maker,
        quantity: quantity,
        priceCents: price,
        makerFeeCents: makerFee,
        takerFeeCents: takerFee,
      ));
      remaining -= quantity;
    }
    if (remaining > 0 && taker.kind == TxKind.limit &&
        taker.timeInForce.canRest) {
      final takerCore = forks.putIfAbsent(
          taker.ownerId, () => account(taker.ownerId).fork());
      final rest = takerCore.preview(
        symbol: taker.symbol,
        side: taker.side,
        quantity: remaining,
        priceCents: taker.limitPriceCents!,
        gameDay: gameDay,
        minuteOfDay: minuteOfDay,
        reduceOnly: taker.reduceOnly,
        feeCents: feePolicy.feeCents(
          profile: profile,
          symbol: taker.symbol,
          quantity: remaining,
          priceCents: taker.limitPriceCents!,
          maker: true,
        ),
      );
      if (!rest.accepted) return _VenueSimulation.reason(rest.reason!);
    }
    return _VenueSimulation(
        forks: forks, trades: trades, remaining: remaining, reason: null);
  }

  TxMarketVenueOrder _reject(_VenueOrder order, String reason) {
    order.status = TxStatus.rejected;
    order.rejectReason = reason;
    order.remaining = order.quantity;
    checkInvariants();
    return order.freeze();
  }

  void _refresh(_VenueOrder order) {
    if (order.remaining == 0) {
      order.status = TxStatus.filled;
    } else if (order.filled > 0) {
      order.status = TxStatus.partiallyFilled;
    }
  }

  void _touchBook() {
    _bookRevision++;
    _depthCache.clear();
    _depthCacheRevision = _bookRevision;
  }
}

class _VenueOrder {
  _VenueOrder({
    required this.id,
    required this.ownerId,
    required this.symbol,
    required this.side,
    required this.kind,
    required this.quantity,
    required this.limitPriceCents,
    required this.timeInForce,
    required this.sequence,
    required this.reduceOnly,
  }) : remaining = quantity;

  final String id;
  final String ownerId;
  final String symbol;
  final TxSide side;
  final TxKind kind;
  final int quantity;
  final int? limitPriceCents;
  final TxTimeInForce timeInForce;
  final int sequence;
  final bool reduceOnly;
  int remaining;
  TxStatus status = TxStatus.open;
  String? rejectReason;

  int get filled => quantity - remaining;

  bool sameRequest(String owner, String instrument, TxSide direction,
      TxKind orderKind, int size, int? price, TxTimeInForce tif,
      bool reduce) => ownerId == owner && symbol == instrument &&
      side == direction && kind == orderKind && quantity == size &&
      limitPriceCents == price && timeInForce == tif && reduceOnly == reduce;

  TxMarketVenueOrder freeze() => TxMarketVenueOrder(
    id: id,
    ownerId: ownerId,
    symbol: symbol,
    side: side,
    kind: kind,
    timeInForce: timeInForce,
    quantity: quantity,
    remaining: remaining,
    limitPriceCents: limitPriceCents,
    sequence: sequence,
    status: status,
    reduceOnly: reduceOnly,
    rejectReason: rejectReason,
  );
}

class _VenueTrade {
  const _VenueTrade({required this.maker, required this.quantity,
    required this.priceCents, required this.makerFeeCents,
    required this.takerFeeCents});
  final _VenueOrder maker;
  final int quantity;
  final int priceCents;
  final int makerFeeCents;
  final int takerFeeCents;
}

class _VenueSimulation {
  const _VenueSimulation({required this.forks, required this.trades,
    required this.remaining, required this.reason});
  final Map<String, TxMarketCore> forks;
  final List<_VenueTrade> trades;
  final int remaining;
  final String? reason;

  factory _VenueSimulation.reason(String message) => _VenueSimulation(
      forks: const {}, trades: const [], remaining: -1, reason: message);
}
