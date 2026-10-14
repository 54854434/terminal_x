/// Single-device, deterministic simulated trading session.
/// Existing JSON snapshots remain schema-compatible and are never reset.
import 'dart:convert';
import 'tx_engine.dart';
import '../market/tx_npc_market.dart';
import '../market/tx_market_session_schedule.dart';
import '../market/tx_realtime_clock.dart';

class TxSession {
  TxSession._(
    this.engine,
    this.step,
    this.referenceCents,
    this.nextPlayerOrder,
    this.archivedLegacyOrders,
    this.archivedLegacyTrades,
    this.isLegacyUpgrade,
  );

  static const symbols = ['SIM-A01', 'SIM-A02'];
  static const playerId = 'PLAYER';
  static const saveKey = 'terminal_x_v01b_state';
  static const oldSaveKey = 'terminal_state';
  static const schemaVersion = 1;

  /// The connected Rust core is the A-share spot book. Its session rule is
  /// enforced at order and minute boundaries; other market profiles are
  /// handled by their own isolated venue/runtime at the terminal boundary.
  static TxMarketSessionStatus marketSessionStatusAt({
    required int committedStep,
    int fractionalSeconds = 0,
  }) {
    final day = TxRealtimeClock.gameDay(committedStep, fractionalSeconds);
    final minute = TxRealtimeClock.gameMinuteOfDay(
        committedStep, fractionalSeconds);
    return TxMarketSessionSchedules.aShare.status(
        gameDay: day, minuteOfDay: minute);
  }

  TxMarketSessionStatus get marketSessionStatus =>
      marketSessionStatusAt(committedStep: step);

  final TxEngine engine;
  int step;
  final List<int> referenceCents;
  int nextPlayerOrder;
  final List<Map<String, dynamic>> archivedLegacyOrders;
  final List<String> archivedLegacyTrades;
  final bool isLegacyUpgrade;
  /// Rust primary matching command log; persists only in the dedicated Rust
  /// game database. Values use integer cents, signed quantities and string IDs.
  /// Never contains pointers or runtime-specific handles.
  final List<List<Object?>> nativeEvents = <List<Object?>>[];
  // The previous successfully committed Rust journal length is volatile. A
  // TXD1 v2 storage delta appends only new commands, while full snapshots
  // and exportJson continue to include the complete deterministic journal.
  int _committedNativeEventCount = 0;

  Map<String, dynamic> snapshotNativeJournalDelta() {
    if (_committedNativeEventCount < 0 ||
        _committedNativeEventCount > nativeEvents.length) {
      throw StateError('Rust journal cursor rewound before SQLite commit');
    }
    return <String, dynamic>{
      'oldLength': _committedNativeEventCount,
      'append': nativeEvents.sublist(_committedNativeEventCount),
    };
  }
  int _quoteFillStart = 0;
  // 0 for a fully closed minute. Positive when verified Rust orders have
  // already executed in the upcoming minute. Stored inside schema-1 JSON.
  int lastPulseSecond = 0;
  int get marketTimeStep => step + (lastPulseSecond > 0 ? 1 : 0);
  // Volatile per-symbol quote cursor. Cached values NEVER enter JSON, Rust
  // events, stored OHLC or the executable order book. A new minute or a
  // previously unseen fill invalidates only the appropriate part of it.
  int _lastPriceCursor = -1;
  int _lastPriceCursorStart = -1;
  final Map<String, int> _minuteLastFillPrice = <String, int>{};

  static TxSession fresh() {
    final e = TxEngine();
    e.registerAccount(playerId, cashCents: 100000000);
    e.registerAccount('LP_A', cashCents: 300000000, shares: {symbols[0]: 25000});
    e.registerAccount('LP_B', cashCents: 300000000, shares: {symbols[1]: 2500});
    final result = TxSession._(e, 0, [1000, 2500], 1, [], [], false);
    result._quoteMakers();
    return result;
  }

  /// New, separately installed market-simulation preview only.
  /// Older tests and V0.1/V0.2 sessions retain their original fresh() book.
  static TxSession freshWithAgents() {
    final session = fresh();
    TxNpcMarket.registerNewAccounts(session.engine);
    session.engine.checkInvariants();
    return session;
  }

  /// Read-only legacy import is retained for tests and old flows, but the
  /// isolated V0.2.1 app always creates or opens its own fresh SQLite account.
  static TxSession fromLegacyJson(String oldJson) {
    final data = Map<String, dynamic>.from(jsonDecode(oldJson) as Map);
    final oldCash = _validLegacyMoney(data['cash'], 'cash');
    final prices = data['prices'] as List;
    final holdings = data['owned'] as List;
    if (prices.length != 2 || holdings.length != 2) {
      throw const FormatException('Invalid legacy symbol count');
    }
    final priceCents = <int>[];
    final shares = <String, int>{};
    for (var i = 0; i < 2; i++) {
      priceCents.add(_validLegacyMoney(prices[i], 'price'));
      final qty = holdings[i];
      if (qty is! int || qty < 0 || qty > TxEngine.maxQuantity) {
        throw const FormatException('Invalid legacy holdings');
      }
      shares[symbols[i]] = qty;
    }
    final oldStep = data['step'];
    if (oldStep is! int || oldStep < 0) {
      throw const FormatException('Invalid legacy clock');
    }
    final pendingRaw = data['pending'] as List;
    final tradeRaw = data['trades'] as List;
    final archive = pendingRaw.map((o) =>
        Map<String, dynamic>.from(o as Map)).toList();
    final tradeArchive = tradeRaw.map((o) => o as String).toList();
    final e = TxEngine();
    e.registerAccount(playerId, cashCents: oldCash, shares: shares);
    e.registerAccount('LP_A', cashCents: 300000000, shares: {symbols[0]: 25000});
    e.registerAccount('LP_B', cashCents: 300000000, shares: {symbols[1]: 2500});
    final session = TxSession._(
      e, oldStep, priceCents, 1, archive, tradeArchive, true,
    );
    session._quoteMakers();
    return session;
  }

  /// V0.2.2 showcases several market phases within a one-hour session.
  /// All transitions depend solely on the saved minute and symbol.
  static const int marketRegimeMinutes = 20;

  static int marketRegime(int minute, int symbolIndex) {
    if (minute < 1 || symbolIndex < 0 || symbolIndex >= symbols.length) {
      throw ArgumentError('Invalid simulation minute or symbol');
    }
    return ((minute - 1) ~/ marketRegimeMinutes + symbolIndex * 2) % 4;
  }

  /// Keep the older passive-mode pricing rule stable for existing tests.
  static int referenceMove(int minute, int symbolIndex) {
    if (minute < 1 || symbolIndex < 0 || symbolIndex >= symbols.length) {
      throw ArgumentError('Invalid simulation minute or symbol');
    }
    final regime = ((minute - 1) ~/ 120 + symbolIndex * 2) % 4;
    return _moveForRegime(minute, symbolIndex, regime);
  }

  static int activeReferenceMove(int minute, int symbolIndex) =>
      _moveForRegime(minute, symbolIndex, marketRegime(minute, symbolIndex));

  static int _moveForRegime(int minute, int symbolIndex, int regime) {
    final mix = ((minute * 1103515245 + symbolIndex * 12345 + 1013904223)
        ^ (minute * 2654435761)) & 0x7fffffff;
    final noise = ((mix ^ (mix >> 7) ^ (mix >> 13)) % 13) - 6;
    switch (regime) {
      case 0: return 2 + noise * 2;  // upward regime
      case 1: return noise;          // quiet range
      case 2: return -2 + noise * 2; // downward regime
      default: return noise * 4;    // wide and volatile
    }
  }

  /// Executes actual funded NPC quotes/trades in the NEXT displayed minute.
  /// The step counter changes only at the minute boundary; marketTimeStep
  /// attributes the confirmed subminute fills to the correct candle.
  /// Repeated pulses after restart are inert and cannot create duplicate IDs.
  void marketPulse(int second) {
    if (second < 5 || second >= 60) {
      throw ArgumentError.value(second, 'second');
    }
    if (second <= lastPulseSecond) return;
    // Pulses are stored against the next displayed market minute. Never
    // create an intraminute candidate whose persisted candle is outside the
    // connected A-share session.
    if (!marketSessionStatusAt(committedStep: step + 1).isOpen) {
      lastPulseSecond = second;
      _quoteFillStart = engine.fillCount;
      return;
    }
    if (!TxNpcMarket.isEnabled(engine)) {
      lastPulseSecond = second;
      return;
    }
    engine.runCheckedMinute(() {
      if (lastPulseSecond == 0) _quoteFillStart = engine.fillCount;
      TxNpcMarket.cancelResting(engine);
      // Unique event seed per game-minute/pulse; never reuse minute-order IDs.
      final seed = (step + 1) * 64 + second;
      final movements = <int>[
        for (var i = 0; i < symbols.length; i++)
          activeReferenceMove(step + 1, i),
      ];
      TxNpcMarket.tradeMinute(
          engine, seed, symbols, referenceCents, movements,
          eventKey: 'P-${step + 1}-$second');
      lastPulseSecond = second;
    });
  }

  void nextTick() {
    // Defer full O(history) checks across this one isolated minute only.
    engine.runCheckedMinute(() {
    TxNpcMarket.cancelResting(engine);
    // Reproduce the old global insertion order while inspecting only resting
    // orders; ledger line order stays byte-for-byte deterministic across upgrades.
    final restingMakerOrders = engine.activeOrders.where((o) =>
        o.ownerId.startsWith('LP_')).toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final order in restingMakerOrders) {
      engine.cancel(order.id, ownerId: order.ownerId);
    }
    final hadPulses = lastPulseSecond > 0;
    step++;
    if (!hadPulses) _quoteFillStart = engine.fillCount;
    lastPulseSecond = 0;
    final sessionOpen = marketSessionStatus.isOpen;
    if (!sessionOpen) {
      // Participant liquidity is withdrawn through the cancellations above;
      // player GTC orders remain reserved for the next open boundary.
      return;
    }
    final movements = <int>[];
    final activeParticipants = TxNpcMarket.isEnabled(engine);
    for (var i = 0; i < symbols.length; i++) {
      final move = activeParticipants
          ? activeReferenceMove(step, i) : referenceMove(step, i);
      movements.add(move);
      referenceCents[i] = (referenceCents[i] + move)
          .clamp(10, 1000000).toInt();
    }
    _quoteMakers();
    TxNpcMarket.tradeMinute(
        engine, step, symbols, referenceCents, movements,
        eventKey: 'T-$step');
    });
  }

  /// Skip only the empty part of the current closed session.
  ///
  /// The returned session stops at the last minute before the next opening
  /// boundary. The following ordinary [nextTick] still performs the real
  /// participant quotes/trades for that opening minute. No price, fill or
  /// reference mark is fabricated while time is skipped.
  int fastForwardClosed() {
    if (marketSessionStatus.isOpen) return 0;
    final initialStep = step;
    var nextOpenStep = step + 1;
    const maxSearchMinutes = 10080;
    while (!marketSessionStatusAt(committedStep: nextOpenStep).isOpen) {
      nextOpenStep++;
      if (nextOpenStep - initialStep > maxSearchMinutes) {
        throw StateError('No next market opening found within one game week');
      }
    }
    final targetStep = nextOpenStep - 1;
    if (targetStep <= step) return 0;

    // A normal closed-minute tick withdraws participant liquidity first. Do
    // the same in this atomic shortcut so a Rust-backed worker never jumps
    // over a live maker order without sending its cancellation through the
    // native gate. Player GTC orders remain reserved for the next open.
    engine.runCheckedMinute(() {
      TxNpcMarket.cancelResting(engine);
      final restingMakerOrders = engine.activeOrders.where((order) =>
          order.ownerId.startsWith('LP_')).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      for (final order in restingMakerOrders) {
        engine.cancel(order.id, ownerId: order.ownerId);
      }
    });
    step = targetStep;
    lastPulseSecond = 0;
    _quoteFillStart = engine.fillCount;
    _lastPriceCursor = -1;
    _lastPriceCursorStart = -1;
    _minuteLastFillPrice.clear();
    engine.checkInvariants();
    return targetStep - initialStep;
  }

  void _quoteMakers() {
    for (var i = 0; i < symbols.length; i++) {
      final owner = i == 0 ? 'LP_A' : 'LP_B';
      final sizes = i == 0
          ? [100, 200, 300, 450, 600]
          : [20, 35, 50, 60, 80];
      // Historical fresh()/legacy sessions retain their exact old maker
      // book. Agent-enabled sessions revise genuine, fully funded orders
      // once per committed game minute. This is NOT a painted fake depth:
      // every price/quantity goes through ordinary engine.place().
      final dynamicBook = step > 0 && TxNpcMarket.isEnabled(engine);
      final account = engine.account(owner);
      for (var level = 1; level <= 5; level++) {
        for (final side in [TxSide.sell, TxSide.buy]) {
          final seed = ((step * 1103515245 + i * 123457 + level * 7919 +
                  (side == TxSide.buy ? 104729 : 15485863)) & 0x7fffffff);
          final depthOffset = dynamicBook ? seed % 3 : 0;
          final distance = level + depthOffset;
          final price = referenceCents[i] +
              (side == TxSide.sell ? distance : -distance);
          if (price <= 0 || price > TxEngine.maxPriceCents) continue;
          final scale = dynamicBook ? (65 + (seed ~/ 97) % 76) : 100;
          var quantity = sizes[level - 1] * scale ~/ 100;
          if (side == TxSide.sell) {
            quantity = quantity > account.availableSharesOf(symbols[i])
                ? account.availableSharesOf(symbols[i]) : quantity;
          } else {
            final affordable = account.availableCashCents ~/ price;
            quantity = quantity > affordable ? affordable : quantity;
          }
          if (quantity <= 0) continue;
          engine.place(
            id: 'LP-$i-$step-${side.name}-$level',
            ownerId: owner,
            symbol: symbols[i],
            side: side,
            kind: TxKind.limit,
            quantity: quantity,
            limitPriceCents: price,
          );
        }
      }
    }
  }

  TxOrder placePlayer({
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    int? limitPriceCents,
    TxTimeInForce timeInForce = TxTimeInForce.gtc,
  }) {
    if (!symbols.contains(symbol)) throw ArgumentError('Unsupported symbol');
    final sessionStatus = marketSessionStatus;
    if (!sessionStatus.isOpen) {
      throw StateError('A股${sessionStatus.label}，暂不可下单');
    }
    return engine.place(
      id: 'PLAYER-${nextPlayerOrder++}',
      ownerId: playerId,
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
      timeInForce: timeInForce,
    );
  }

  TxOrder cancelPlayer(String orderId) =>
      engine.cancel(orderId, ownerId: playerId);

  int lastPrice(String symbol) {
    final fillCount = engine.fillCount;
    if (_lastPriceCursorStart != _quoteFillStart ||
        _lastPriceCursor > fillCount || _lastPriceCursor < _quoteFillStart) {
      _minuteLastFillPrice.clear();
      _lastPriceCursorStart = _quoteFillStart;
      _lastPriceCursor = _quoteFillStart;
    }
    // Only process NEW fills since the previous read, in execution order.
    // Reading the chart quote at 60/120 FPS is now O(1) after the first read.
    for (var i = _lastPriceCursor; i < fillCount; i++) {
      final fill = engine.fillAt(i);
      _minuteLastFillPrice[fill.symbol] = fill.priceCents;
    }
    _lastPriceCursor = fillCount;
    return _minuteLastFillPrice[symbol] ??
        referenceCents[symbols.indexOf(symbol)];
  }

  /// Real fills since the start of the most recent simulated minute.
  /// No fake print events and no exposure of historical NPC order payloads.
  List<TxFill> get currentMinuteFills =>
      List<TxFill>.generate(engine.fillCount - _quoteFillStart,
        (i) => engine.fillAt(_quoteFillStart + i), growable: false);

  int get totalAssetsCents {
    final player = engine.account(playerId);
    return player.cashCents +
        symbols.fold<int>(0, (sum, s) => sum + player.sharesOf(s) * lastPrice(s));
  }

  List<TxOrder> get playerOrders {
    final list = engine.orders.values.where((o) => o.ownerId == playerId).toList();
    list.sort((a, b) => b.sequence.compareTo(a.sequence));
    return list;
  }

  /// Newest [limit] player orders, without sorting / allocating the entire
  /// historical order collection. A min-heap retains the top K sequences.
  /// Work O(all orders * log(limit)), extra memory O(limit).
  List<TxOrder> recentPlayerOrders({int limit = 100}) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    final heap = <TxOrder>[];
    for (final order in engine.orders.values) {
      if (order.ownerId != playerId) continue;
      if (heap.length < limit) {
        heap.add(order);
        var i = heap.length - 1;
        while (i > 0) {
          final parent = (i - 1) ~/ 2;
          if (heap[parent].sequence <= heap[i].sequence) break;
          final temp = heap[parent];
          heap[parent] = heap[i];
          heap[i] = temp;
          i = parent;
        }
      } else if (order.sequence > heap[0].sequence) {
        heap[0] = order;
        var i = 0;
        while (true) {
          final left = 2 * i + 1;
          if (left >= heap.length) break;
          final right = left + 1;
          var smallest = left;
          if (right < heap.length &&
              heap[right].sequence < heap[left].sequence) {
            smallest = right;
          }
          if (heap[i].sequence <= heap[smallest].sequence) break;
          final temp = heap[i];
          heap[i] = heap[smallest];
          heap[smallest] = temp;
          i = smallest;
        }
      }
    }
    heap.sort((a, b) => b.sequence.compareTo(a.sequence));
    return heap;
  }

  /// Outstanding player orders only; avoid sorting historical filled and
  /// cancelled orders whenever the trade page rebuilds after a minute.
  List<TxOrder> get activePlayerOrders {
    final active = <TxOrder>[];
    for (final order in engine.activeOrders) {
      if (order.ownerId == playerId) active.add(order);
    }
    active.sort((a, b) => b.sequence.compareTo(a.sequence));
    return active;
  }

  // Bounded, newest-first record query. Unlike playerFills, it stops once
  // [limit] matching REAL fills are found, without collecting the whole past.
  // Neither the authoritative fill stream nor the on-disk schema is changed.
  List<TxFill> recentPlayerFills({int limit = 100}) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    final result = <TxFill>[];
    for (var i = engine.fillCount - 1; i >= 0; i--) {
      final fill = engine.fillAt(i);
      if (engine.order(fill.buyOrderId).ownerId == playerId ||
          engine.order(fill.sellOrderId).ownerId == playerId) {
        result.add(fill);
        if (result.length == limit) break;
      }
    }
    return result;
  }

  // Public historical API remains complete, as before.
  List<TxFill> get playerFills =>
      recentPlayerFills(limit: engine.fillCount == 0 ? 1 : engine.fillCount);

  /// Session-only snapshot fields for O(changed-records) delta encoding.
  Map<String, dynamic> snapshotHeader() => <String, dynamic>{
        'schema': schemaVersion,
        'step': step,
        'referenceCents': referenceCents,
        'nextPlayerOrder': nextPlayerOrder,
        'quoteFillStart': _quoteFillStart,
        'lastPulseSecond': lastPulseSecond,
        'archivedLegacyOrders': archivedLegacyOrders,
        'archivedLegacyTrades': archivedLegacyTrades,
        'isLegacyUpgrade': isLegacyUpgrade,
        'nativeEvents': nativeEvents,
      };

  /// Establish a new delta base AFTER an atomic SQLite commit.
  /// Kept separate from the economic state and never serialized.
  void acknowledgeCommittedSnapshot() {
    engine.acknowledgeCommittedSnapshot();
    _committedNativeEventCount = nativeEvents.length;
  }

  /// R31: validate the already-typed candidate directly, without spending an
  /// additional full JSON export/import cycle before every SQLite save.
  /// All invariants remain checked in release mode, not just debug asserts.
  void checkInvariantsForCommit() {
    if (step < 0 || referenceCents.length != symbols.length ||
        referenceCents.any((value) => value <= 0) || nextPlayerOrder < 1 ||
        _quoteFillStart < 0 || _quoteFillStart > engine.fillCount ||
        lastPulseSecond < 0 || lastPulseSecond >= 60 ||
        (lastPulseSecond > 0 && lastPulseSecond < 5)) {
      throw StateError('Invalid session metadata before SQLite commit');
    }
    for (final id in <String>[playerId, 'LP_A', 'LP_B']) {
      engine.account(id);
    }
    // The market worker already fully audits at the end of every minute;
    // a standalone player order also audits before returning. Audit again
    // only if a subsequent economic mutation invalidated the trust stamp.
    engine.verifyBeforeCommit();
  }

  String exportJson() => jsonEncode({
        ...snapshotHeader(),
        'engine': engine.exportJson(),
      });

  static TxSession importJson(String raw) {
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (data['schema'] != schemaVersion) {
      throw const FormatException('Unsupported session snapshot version');
    }
    final references = (data['referenceCents'] as List).map((v) => v as int).toList();
    final step = data['step'] as int;
    final counter = data['nextPlayerOrder'] as int;
    if (references.length != 2 || references.any((v) => v <= 0) ||
        step < 0 || counter < 1) {
      throw const FormatException('Invalid session metadata');
    }
    final engine = TxEngine.importJson(data['engine'] as String);
    final quoteFillStart = data['quoteFillStart'] as int;
    if (quoteFillStart < 0 || quoteFillStart > engine.fillCount) {
      throw const FormatException('Invalid fill cursor');
    }
    for (final id in [playerId, 'LP_A', 'LP_B']) {
      engine.account(id);
    }
    final archivedOrders = (data['archivedLegacyOrders'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map)).toList();
    final archivedTrades = (data['archivedLegacyTrades'] as List)
        .map((v) => v as String).toList();
    final session = TxSession._(engine, step, references, counter,
        archivedOrders, archivedTrades, data['isLegacyUpgrade'] as bool)
      .._quoteFillStart = quoteFillStart;
    final pulseSecond = data['lastPulseSecond'] ?? 0;
    if (pulseSecond is! int || pulseSecond < 0 || pulseSecond >= 60 ||
        (pulseSecond > 0 && pulseSecond < 5)) {
      throw const FormatException('Invalid committed market pulse second');
    }
    session.lastPulseSecond = pulseSecond;
    final rawEvents = data['nativeEvents'];
    if (rawEvents is List) {
      for (final event in rawEvents) {
        if (event is! List || event.isEmpty || event.length > 9) {
          throw const FormatException('Invalid Rust journal row');
        }
        session.nativeEvents.add(List<Object?>.from(event));
      }
    }
    session._committedNativeEventCount = session.nativeEvents.length;
    return session;
  }
}

int _validLegacyMoney(Object? n, String context) {
  if (n is! num || !n.isFinite || n < 0 || n * 100 > TxEngine.maxNotionalCents) {
    throw FormatException('Invalid legacy $context');
  }
  final cents = (n * 100).round();
  if (context == 'price' && (cents < 1 || cents > TxEngine.maxPriceCents)) {
    throw FormatException('Invalid legacy price');
  }
  return cents;
}
