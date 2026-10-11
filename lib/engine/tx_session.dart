/// Single-device, deterministic simulated trading session.
/// Existing JSON snapshots remain schema-compatible and are never reset.
import 'dart:convert';
import 'tx_engine.dart';

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

  final TxEngine engine;
  int step;
  final List<int> referenceCents;
  int nextPlayerOrder;
  final List<Map<String, dynamic>> archivedLegacyOrders;
  final List<String> archivedLegacyTrades;
  final bool isLegacyUpgrade;
  int _quoteFillStart = 0;

  static TxSession fresh() {
    final e = TxEngine();
    e.registerAccount(playerId, cashCents: 100000000);
    e.registerAccount('LP_A', cashCents: 300000000, shares: {symbols[0]: 25000});
    e.registerAccount('LP_B', cashCents: 300000000, shares: {symbols[1]: 2500});
    final result = TxSession._(e, 0, [1000, 2500], 1, [], [], false);
    result._quoteMakers();
    return result;
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

  /// The upgraded market model is deterministic from the saved simulation step;
  /// no wall clock, mutable PRNG state or external market data is involved.
  /// Trend regimes rotate every 120 simulated minutes. No false fills are made.
  static int referenceMove(int minute, int symbolIndex) {
    if (minute < 1 || symbolIndex < 0 || symbolIndex >= symbols.length) {
      throw ArgumentError('Invalid simulation minute or symbol');
    }
    final regime = ((minute - 1) ~/ 120 + symbolIndex * 2) % 4;
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

  void nextTick() {
    final restingMakerOrders = engine.orders.values.where((o) =>
        o.ownerId.startsWith('LP_') &&
        (o.status == TxStatus.open || o.status == TxStatus.partiallyFilled))
        .map((o) => o.id).toList();
    for (final id in restingMakerOrders) {
      final order = engine.order(id);
      engine.cancel(id, ownerId: order.ownerId);
    }
    step++;
    _quoteFillStart = engine.fills.length;
    for (var i = 0; i < symbols.length; i++) {
      referenceCents[i] = (referenceCents[i] + referenceMove(step, i))
          .clamp(10, 1000000).toInt();
    }
    _quoteMakers();
    engine.checkInvariants();
  }

  void _quoteMakers() {
    for (var i = 0; i < symbols.length; i++) {
      final owner = i == 0 ? 'LP_A' : 'LP_B';
      final sizes = i == 0
          ? [100, 200, 300, 450, 600]
          : [20, 35, 50, 60, 80];
      for (var level = 1; level <= 5; level++) {
        for (final side in [TxSide.sell, TxSide.buy]) {
          final price = referenceCents[i] + (side == TxSide.sell ? level : -level);
          if (price <= 0) continue;
          engine.place(
            id: 'LP-$i-$step-${side.name}-$level',
            ownerId: owner,
            symbol: symbols[i],
            side: side,
            kind: TxKind.limit,
            quantity: sizes[level - 1],
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
  }) {
    if (!symbols.contains(symbol)) throw ArgumentError('Unsupported symbol');
    return engine.place(
      id: 'PLAYER-${nextPlayerOrder++}',
      ownerId: playerId,
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
    );
  }

  TxOrder cancelPlayer(String orderId) =>
      engine.cancel(orderId, ownerId: playerId);

  int lastPrice(String symbol) {
    for (var i = engine.fills.length - 1; i >= _quoteFillStart; i--) {
      final fill = engine.fills[i];
      if (fill.symbol == symbol) return fill.priceCents;
    }
    return referenceCents[symbols.indexOf(symbol)];
  }

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

  List<TxFill> get playerFills => engine.fills.reversed.where((f) =>
      engine.order(f.buyOrderId).ownerId == playerId ||
      engine.order(f.sellOrderId).ownerId == playerId).toList();

  String exportJson() => jsonEncode({
        'schema': schemaVersion,
        'step': step,
        'referenceCents': referenceCents,
        'nextPlayerOrder': nextPlayerOrder,
        'quoteFillStart': _quoteFillStart,
        'archivedLegacyOrders': archivedLegacyOrders,
        'archivedLegacyTrades': archivedLegacyTrades,
        'isLegacyUpgrade': isLegacyUpgrade,
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
    if (quoteFillStart < 0 || quoteFillStart > engine.fills.length) {
      throw const FormatException('Invalid fill cursor');
    }
    for (final id in [playerId, 'LP_A', 'LP_B']) {
      engine.account(id);
    }
    final archivedOrders = (data['archivedLegacyOrders'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map)).toList();
    final archivedTrades = (data['archivedLegacyTrades'] as List)
        .map((v) => v as String).toList();
    return TxSession._(engine, step, references, counter,
        archivedOrders, archivedTrades, data['isLegacyUpgrade'] as bool)
      .._quoteFillStart = quoteFillStart;
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
