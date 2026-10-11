/// Terminal X V0.1b: deterministic, single-isolate, in-memory matching engine.
///
/// No Flutter dependency. Currency is integer cents, quantity is integer shares.
/// All external liquidity must be entered by a funded participant account.
/// Does NOT migrate legacy app saves or persist by itself.
import 'dart:convert';
import 'dart:math' as math;

enum TxSide { buy, sell }
enum TxKind { limit, market }
enum TxStatus { open, partiallyFilled, filled, cancelled, rejected }

class TxAccount {
  TxAccount._(this.id, int openingCashCents, Map<String, int> openingShares)
      : _openingCashCents = openingCashCents,
        _cashCents = openingCashCents,
        _openingShares = Map<String, int>.from(openingShares),
        _shares = Map<String, int>.from(openingShares);

  final String id;
  final int _openingCashCents;
  final Map<String, int> _openingShares;
  int _cashCents;
  final Map<String, int> _shares;
  int _reservedCashCents = 0;
  final Map<String, int> _reservedShares = {};

  int get cashCents => _cashCents;
  int get reservedCashCents => _reservedCashCents;
  int get availableCashCents => _cashCents - _reservedCashCents;
  int sharesOf(String symbol) => _shares[symbol] ?? 0;
  int reservedSharesOf(String symbol) => _reservedShares[symbol] ?? 0;
  int availableSharesOf(String symbol) =>
      sharesOf(symbol) - reservedSharesOf(symbol);
  Map<String, int> get shares => Map.unmodifiable(_shares);
  Map<String, int> get reservedShares => Map.unmodifiable(_reservedShares);

  Map<String, dynamic> toJson() => {
        'id': id,
        'openingCashCents': _openingCashCents,
        'openingShares': _openingShares,
        'cashCents': _cashCents,
        'shares': _shares,
        'reservedCashCents': _reservedCashCents,
        'reservedShares': _reservedShares,
      };

  static TxAccount fromJson(Map<String, dynamic> data) {
    final account = TxAccount._(
      data['id'] as String,
      data['openingCashCents'] as int,
      _intMap(data['openingShares']),
    );
    account._cashCents = data['cashCents'] as int;
    account._shares
      ..clear()
      ..addAll(_intMap(data['shares']));
    account._reservedCashCents = data['reservedCashCents'] as int;
    account._reservedShares.addAll(_intMap(data['reservedShares']));
    return account;
  }
}

class TxOrder {
  TxOrder._({
    required this.id,
    required this.ownerId,
    required this.symbol,
    required this.side,
    required this.kind,
    required int quantity,
    required this.limitPriceCents,
    required this.sequence,
  }) : quantity = quantity, _remaining = quantity;

  final String id;
  final String ownerId;
  final String symbol;
  final TxSide side;
  final TxKind kind;
  final int quantity;
  final int? limitPriceCents;
  final int sequence;
  int _remaining;
  TxStatus _status = TxStatus.open;
  String? _rejectReason;
  int get remaining => _remaining;
  TxStatus get status => _status;
  String? get rejectReason => _rejectReason;
  int get filled => quantity - _remaining;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerId': ownerId,
        'symbol': symbol,
        'side': side.name,
        'kind': kind.name,
        'quantity': quantity,
        'limitPriceCents': limitPriceCents,
        'sequence': sequence,
        'remaining': remaining,
        'status': status.name,
        'rejectReason': rejectReason,
      };

  static TxOrder fromJson(Map<String, dynamic> data) {
    final order = TxOrder._(
      id: data['id'] as String,
      ownerId: data['ownerId'] as String,
      symbol: data['symbol'] as String,
      side: TxSide.values.byName(data['side'] as String),
      kind: TxKind.values.byName(data['kind'] as String),
      quantity: data['quantity'] as int,
      limitPriceCents: data['limitPriceCents'] as int?,
      sequence: data['sequence'] as int,
    );
    order._remaining = data['remaining'] as int;
    order._status = TxStatus.values.byName(data['status'] as String);
    order._rejectReason = data['rejectReason'] as String?;
    return order;
  }
}

class TxFill {
  const TxFill({
    required this.id,
    required this.symbol,
    required this.buyOrderId,
    required this.sellOrderId,
    required this.quantity,
    required this.priceCents,
  });
  final String id;
  final String symbol;
  final String buyOrderId;
  final String sellOrderId;
  final int quantity;
  final int priceCents;
  int get notionalCents => quantity * priceCents;
  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'buyOrderId': buyOrderId,
        'sellOrderId': sellOrderId,
        'quantity': quantity,
        'priceCents': priceCents,
      };
  static TxFill fromJson(Map<String, dynamic> j) => TxFill(
        id: j['id'] as String,
        symbol: j['symbol'] as String,
        buyOrderId: j['buyOrderId'] as String,
        sellOrderId: j['sellOrderId'] as String,
        quantity: j['quantity'] as int,
        priceCents: j['priceCents'] as int,
      );
}

/// Append-only account deltas. A reservation is not a cash debit.
class TxLedgerEntry {
  const TxLedgerEntry({
    required this.accountId,
    required this.symbol,
    required this.reason,
    this.fillId,
    this.cashDeltaCents = 0,
    this.reservedCashDeltaCents = 0,
    this.shareDelta = 0,
    this.reservedShareDelta = 0,
  });
  final String accountId;
  final String symbol;
  final String reason;
  final String? fillId;
  final int cashDeltaCents;
  final int reservedCashDeltaCents;
  final int shareDelta;
  final int reservedShareDelta;
  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'symbol': symbol,
        'reason': reason,
        'fillId': fillId,
        'cashDeltaCents': cashDeltaCents,
        'reservedCashDeltaCents': reservedCashDeltaCents,
        'shareDelta': shareDelta,
        'reservedShareDelta': reservedShareDelta,
      };
  static TxLedgerEntry fromJson(Map<String, dynamic> j) => TxLedgerEntry(
        accountId: j['accountId'] as String,
        symbol: j['symbol'] as String,
        reason: j['reason'] as String,
        fillId: j['fillId'] as String?,
        cashDeltaCents: j['cashDeltaCents'] as int,
        reservedCashDeltaCents: j['reservedCashDeltaCents'] as int,
        shareDelta: j['shareDelta'] as int,
        reservedShareDelta: j['reservedShareDelta'] as int,
      );
}

class TxBookLevel {
  const TxBookLevel(this.priceCents, this.quantity, this.orderCount);
  final int priceCents;
  final int quantity;
  final int orderCount;
}

class TxEngine {
  static const int snapshotVersion = 1;
  static const int maxNotionalCents = 9000000000000000;
  static const int maxQuantity = 100000000;
  static const int maxPriceCents = 1000000000;

  final Map<String, TxAccount> _accounts = {};
  final Map<String, TxOrder> _orders = {};
  final List<TxFill> _fills = [];
  final List<TxLedgerEntry> _ledger = [];
  int _nextOrderSequence = 1;
  int _nextFillSequence = 1;

  Map<String, TxAccount> get accounts => Map.unmodifiable(_accounts);
  Map<String, TxOrder> get orders => Map.unmodifiable(_orders);
  List<TxFill> get fills => List.unmodifiable(_fills);
  List<TxLedgerEntry> get ledger => List.unmodifiable(_ledger);
  TxAccount account(String id) => _accounts[id] ?? (throw StateError('Unknown account: $id'));
  TxOrder order(String id) => _orders[id] ?? (throw StateError('Unknown order: $id'));

  void registerAccount(String id,
      {required int cashCents, Map<String, int> shares = const {}}) {
    if (id.trim().isEmpty || _accounts.containsKey(id)) {
      throw ArgumentError('Account ID missing or duplicate');
    }
    if (cashCents < 0 || cashCents > maxNotionalCents ||
        shares.keys.any((s) => s.trim().isEmpty) ||
        shares.values.any((q) => q < 0 || q > maxQuantity)) {
      throw ArgumentError('Invalid initial account assets');
    }
    _accounts[id] = TxAccount._(id, cashCents, shares);
    checkInvariants();
  }

  TxOrder place({
    required String id,
    required String ownerId,
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    int? limitPriceCents,
  }) {
    if (id.trim().isEmpty) throw ArgumentError('Order ID is required');
    final existing = _orders[id];
    if (existing != null) {
      if (existing.ownerId == ownerId && existing.symbol == symbol &&
          existing.side == side && existing.kind == kind &&
          existing.quantity == quantity &&
          existing.limitPriceCents == limitPriceCents) {
        return existing; // At-least-once delivery: do not re-execute a repeat.
      }
      throw StateError('Conflicting reuse of order ID: $id');
    }
    final incoming = TxOrder._(
      id: id,
      ownerId: ownerId,
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
      sequence: _nextOrderSequence++,
    );
    _orders[id] = incoming;

    String? invalid;
    if (ownerId.trim().isEmpty || !_accounts.containsKey(ownerId)) {
      invalid = 'Unknown account';
    } else if (symbol.trim().isEmpty || quantity <= 0 || quantity > maxQuantity) {
      invalid = 'Invalid symbol or quantity';
    } else if ((kind == TxKind.limit &&
            (limitPriceCents == null || limitPriceCents <= 0 ||
             limitPriceCents > maxPriceCents)) ||
        (kind == TxKind.market && limitPriceCents != null)) {
      invalid = 'Invalid order price/type';
    } else if (kind == TxKind.limit &&
        limitPriceCents! * quantity > maxNotionalCents) {
      invalid = 'Notional exceeds limit';
    }
    if (invalid != null) return _reject(incoming, invalid);

    final owner = _accounts[ownerId]!;
    final matches = _counterparties(incoming);
    var wanted = quantity;
    var marketBuyCost = 0;
    for (final maker in matches) {
      if (wanted == 0) break;
      final take = math.min(wanted, maker.remaining);
      if (maker.ownerId == ownerId) {
        return _reject(incoming, 'Self-trade prevention');
      }
      if (side == TxSide.buy && kind == TxKind.market) {
        marketBuyCost += take * maker.limitPriceCents!;
        if (marketBuyCost > maxNotionalCents) {
          return _reject(incoming, 'Market order notional exceeds limit');
        }
      }
      wanted -= take;
    }
    if (side == TxSide.buy) {
      final requiredCash = kind == TxKind.limit
          ? quantity * limitPriceCents!
          : marketBuyCost;
      if (requiredCash > owner.availableCashCents) {
        return _reject(incoming, 'Insufficient available cash');
      }
      if (kind == TxKind.limit) {
        owner._reservedCashCents += requiredCash;
        _ledger.add(TxLedgerEntry(
            accountId: ownerId, symbol: symbol, reason: 'reserve_buy',
            reservedCashDeltaCents: requiredCash));
      }
    } else {
      if (quantity > owner.availableSharesOf(symbol)) {
        return _reject(incoming, 'Insufficient available shares');
      }
      if (kind == TxKind.limit) {
        owner._reservedShares[symbol] = owner.reservedSharesOf(symbol) + quantity;
        _ledger.add(TxLedgerEntry(
            accountId: ownerId, symbol: symbol, reason: 'reserve_sell',
            reservedShareDelta: quantity));
      }
    }

    for (final maker in matches) {
      if (incoming.remaining == 0) break;
      final take = math.min(incoming.remaining, maker.remaining);
      if (take == 0) continue;
      _execute(incoming, maker, take);
    }
    if (incoming.remaining > 0 && kind == TxKind.market) {
      incoming._status = TxStatus.cancelled; // IOC remainder is never left on book.
    } else {
      _refreshStatus(incoming);
    }
    checkInvariants();
    return incoming;
  }

  TxOrder _reject(TxOrder order, String reason) {
    order._status = TxStatus.rejected;
    order._rejectReason = reason;
    checkInvariants();
    return order;
  }

  /// Cancel an open limit order; an already-cancelled order is idempotent.
  TxOrder cancel(String id, {required String ownerId}) {
    final o = order(id);
    if (o.ownerId != ownerId) throw StateError('Not order owner');
    if (o.status == TxStatus.cancelled) return o;
    if (o.status != TxStatus.open && o.status != TxStatus.partiallyFilled) {
      throw StateError('Order is not open');
    }
    if (o.kind != TxKind.limit) throw StateError('Market order cannot rest');
    final a = account(ownerId);
    if (o.side == TxSide.buy) {
      final release = o.remaining * o.limitPriceCents!;
      a._reservedCashCents -= release;
      _ledger.add(TxLedgerEntry(
          accountId: ownerId, symbol: o.symbol, reason: 'cancel_buy',
          reservedCashDeltaCents: -release));
    } else {
      a._reservedShares[o.symbol] = a.reservedSharesOf(o.symbol) - o.remaining;
      _ledger.add(TxLedgerEntry(
          accountId: ownerId, symbol: o.symbol, reason: 'cancel_sell',
          reservedShareDelta: -o.remaining));
    }
    o._status = TxStatus.cancelled;
    checkInvariants();
    return o;
  }

  List<TxOrder> _counterparties(TxOrder incoming) {
    final list = _orders.values.where((o) {
      if (o.id == incoming.id || o.symbol != incoming.symbol ||
          o.side == incoming.side || o.kind != TxKind.limit ||
          o.remaining <= 0 ||
          (o.status != TxStatus.open && o.status != TxStatus.partiallyFilled)) {
        return false;
      }
      if (incoming.kind == TxKind.market) return true;
      return incoming.side == TxSide.buy
          ? o.limitPriceCents! <= incoming.limitPriceCents!
          : o.limitPriceCents! >= incoming.limitPriceCents!;
    }).toList();
    list.sort((a, b) {
      final price = incoming.side == TxSide.buy
          ? a.limitPriceCents!.compareTo(b.limitPriceCents!)
          : b.limitPriceCents!.compareTo(a.limitPriceCents!);
      return price != 0 ? price : a.sequence.compareTo(b.sequence);
    });
    return list;
  }

  void _execute(TxOrder taker, TxOrder maker, int quantity) {
    final buyerOrder = taker.side == TxSide.buy ? taker : maker;
    final sellerOrder = taker.side == TxSide.sell ? taker : maker;
    final buyer = account(buyerOrder.ownerId);
    final seller = account(sellerOrder.ownerId);
    final price = maker.limitPriceCents!; // Maker-price execution.
    final value = quantity * price;
    if (value > maxNotionalCents || buyer._cashCents < value ||
        seller.sharesOf(taker.symbol) < quantity) {
      throw StateError('Internal preflight/accounting violation');
    }
    final buyerRelease = buyerOrder.kind == TxKind.limit
        ? quantity * buyerOrder.limitPriceCents!
        : 0;
    final sellerRelease = sellerOrder.kind == TxKind.limit ? quantity : 0;
    final fillId = 'F${_nextFillSequence++}';

    buyer._cashCents -= value;
    buyer._reservedCashCents -= buyerRelease;
    buyer._shares[taker.symbol] = buyer.sharesOf(taker.symbol) + quantity;
    seller._cashCents += value;
    seller._shares[taker.symbol] = seller.sharesOf(taker.symbol) - quantity;
    seller._reservedShares[taker.symbol] =
        seller.reservedSharesOf(taker.symbol) - sellerRelease;

    _ledger.add(TxLedgerEntry(
        accountId: buyer.id, symbol: taker.symbol, reason: 'fill_buy',
        fillId: fillId, cashDeltaCents: -value,
        reservedCashDeltaCents: -buyerRelease, shareDelta: quantity));
    _ledger.add(TxLedgerEntry(
        accountId: seller.id, symbol: taker.symbol, reason: 'fill_sell',
        fillId: fillId, cashDeltaCents: value,
        shareDelta: -quantity, reservedShareDelta: -sellerRelease));
    _fills.add(TxFill(
        id: fillId, symbol: taker.symbol,
        buyOrderId: buyerOrder.id, sellOrderId: sellerOrder.id,
        quantity: quantity, priceCents: price));
    maker._remaining -= quantity;
    taker._remaining -= quantity;
    _refreshStatus(maker);
    _refreshStatus(taker);
  }

  void _refreshStatus(TxOrder order) {
    if (order.remaining == 0) {
      order._status = TxStatus.filled;
    } else if (order.filled > 0) {
      order._status = TxStatus.partiallyFilled;
    } else {
      order._status = TxStatus.open;
    }
  }

  /// True resting liquidity only: never fabricates or replenishes quotes.
  List<TxBookLevel> depth(String symbol, TxSide side, {int levels = 5}) {
    if (levels < 0) throw ArgumentError('levels must be nonnegative');
    final byPrice = <int, List<int>>{};
    for (final o in _orders.values) {
      if (o.symbol != symbol || o.side != side || o.kind != TxKind.limit ||
          o.remaining <= 0 ||
          (o.status != TxStatus.open && o.status != TxStatus.partiallyFilled)) {
        continue;
      }
      final cell = byPrice.putIfAbsent(o.limitPriceCents!, () => [0, 0]);
      cell[0] += o.remaining;
      cell[1] += 1;
    }
    final prices = byPrice.keys.toList()..sort();
    if (side == TxSide.buy) prices.sort((a, b) => b.compareTo(a));
    return prices.take(levels).map((p) =>
        TxBookLevel(p, byPrice[p]![0], byPrice[p]![1])).toList();
  }

  /// Snapshot is an application integration point, not an atomic disk write.
  /// Save it under a NEW key; do not overwrite legacy shared_preferences data.
  String exportJson() => jsonEncode({
        'version': snapshotVersion,
        'nextOrderSequence': _nextOrderSequence,
        'nextFillSequence': _nextFillSequence,
        'accounts': _accounts.values.map((e) => e.toJson()).toList(),
        'orders': _orders.values.map((e) => e.toJson()).toList(),
        'fills': _fills.map((e) => e.toJson()).toList(),
        'ledger': _ledger.map((e) => e.toJson()).toList(),
      });

  static TxEngine importJson(String serialized) {
    final data = Map<String, dynamic>.from(jsonDecode(serialized) as Map);
    if (data['version'] != snapshotVersion) {
      throw FormatException('Unsupported engine snapshot version');
    }
    final engine = TxEngine();
    engine._nextOrderSequence = data['nextOrderSequence'] as int;
    engine._nextFillSequence = data['nextFillSequence'] as int;
    for (final v in data['accounts'] as List) {
      final a = TxAccount.fromJson(Map<String, dynamic>.from(v as Map));
      if (engine._accounts.containsKey(a.id)) throw FormatException('Duplicate account');
      engine._accounts[a.id] = a;
    }
    for (final v in data['orders'] as List) {
      final o = TxOrder.fromJson(Map<String, dynamic>.from(v as Map));
      if (engine._orders.containsKey(o.id)) throw FormatException('Duplicate order');
      engine._orders[o.id] = o;
    }
    engine._fills.addAll((data['fills'] as List).map(
        (v) => TxFill.fromJson(Map<String, dynamic>.from(v as Map))));
    engine._ledger.addAll((data['ledger'] as List).map(
        (v) => TxLedgerEntry.fromJson(Map<String, dynamic>.from(v as Map))));
    engine.checkInvariants();
    return engine;
  }

  /// Explicit checks even in release mode, independent of Dart's `assert` flag.
  void checkInvariants() {
    final expectedCashReserve = <String, int>{};
    final expectedShareReserve = <String, Map<String, int>>{};
    var maxOrderSeq = 0;
    final orderSequences = <int>{};
    for (final o in _orders.values) {
      if (o.sequence <= 0 || !orderSequences.add(o.sequence) ||
          (o.status != TxStatus.rejected &&
              (o.quantity <= 0 || o.quantity > maxQuantity ||
               o.remaining < 0 || o.remaining > o.quantity))) {
        throw StateError('Invalid order quantity or sequence');
      }
      maxOrderSeq = math.max(maxOrderSeq, o.sequence);
      final active = o.status == TxStatus.open || o.status == TxStatus.partiallyFilled;
      if (active && (o.remaining == 0 || o.kind != TxKind.limit ||
          !_accounts.containsKey(o.ownerId))) {
        throw StateError('Invalid active order');
      }
      if ((o.status == TxStatus.filled && o.remaining != 0) ||
          (o.status == TxStatus.open && o.filled != 0) ||
          (o.status == TxStatus.partiallyFilled && (o.filled == 0 || o.remaining == 0)) ||
          (o.status == TxStatus.rejected && o.remaining != o.quantity)) {
        throw StateError('Inconsistent order status');
      }
      if (!active) continue;
      if (o.side == TxSide.buy) {
        expectedCashReserve[o.ownerId] =
            (expectedCashReserve[o.ownerId] ?? 0) + o.remaining * o.limitPriceCents!;
      } else {
        final bySymbol = expectedShareReserve.putIfAbsent(o.ownerId, () => {});
        bySymbol[o.symbol] = (bySymbol[o.symbol] ?? 0) + o.remaining;
      }
    }
    if (_nextOrderSequence <= maxOrderSeq || _nextFillSequence <= _fills.length) {
      throw StateError('Non-monotonic sequence');
    }
    final dCash = <String, int>{};
    final dReservedCash = <String, int>{};
    final dShares = <String, Map<String, int>>{};
    final dReservedShares = <String, Map<String, int>>{};
    for (final line in _ledger) {
      if (!_accounts.containsKey(line.accountId)) {
        throw StateError('Ledger references unknown account');
      }
      dCash[line.accountId] = (dCash[line.accountId] ?? 0) + line.cashDeltaCents;
      dReservedCash[line.accountId] =
          (dReservedCash[line.accountId] ?? 0) + line.reservedCashDeltaCents;
      final shareMap = dShares.putIfAbsent(line.accountId, () => {});
      shareMap[line.symbol] = (shareMap[line.symbol] ?? 0) + line.shareDelta;
      final reserveMap = dReservedShares.putIfAbsent(line.accountId, () => {});
      reserveMap[line.symbol] = (reserveMap[line.symbol] ?? 0) + line.reservedShareDelta;
    }
    for (final a in _accounts.values) {
      if (a._cashCents < 0 || a._reservedCashCents < 0 ||
          a._reservedCashCents > a._cashCents ||
          a._cashCents != a._openingCashCents + (dCash[a.id] ?? 0) ||
          a._reservedCashCents != (dReservedCash[a.id] ?? 0) ||
          a._reservedCashCents != (expectedCashReserve[a.id] ?? 0)) {
        throw StateError('Cash or reserved cash inconsistency: ${a.id}');
      }
      final symbols = <String>{
        ...a._openingShares.keys, ...a._shares.keys, ...a._reservedShares.keys,
        ...?dShares[a.id]?.keys, ...?dReservedShares[a.id]?.keys,
        ...?expectedShareReserve[a.id]?.keys,
      };
      for (final symbol in symbols) {
        final q = a.sharesOf(symbol);
        final locked = a.reservedSharesOf(symbol);
        if (q < 0 || locked < 0 || locked > q ||
            q != (a._openingShares[symbol] ?? 0) + (dShares[a.id]?[symbol] ?? 0) ||
            locked != (dReservedShares[a.id]?[symbol] ?? 0) ||
            locked != (expectedShareReserve[a.id]?[symbol] ?? 0)) {
          throw StateError('Shares/reservation inconsistency: ${a.id}/$symbol');
        }
      }
    }
    final seenFills = <String>{};
    var lastFillSeq = 0;
    for (final fill in _fills) {
      final seq = int.tryParse(fill.id.substring(1));
      if (fill.quantity <= 0 || fill.priceCents <= 0 ||
          fill.notionalCents > maxNotionalCents ||
          seq == null || seq <= lastFillSeq || !seenFills.add(fill.id) ||
          !_orders.containsKey(fill.buyOrderId) ||
          !_orders.containsKey(fill.sellOrderId)) {
        throw StateError('Invalid fill record');
      }
      lastFillSeq = seq;
      final buy = _orders[fill.buyOrderId]!;
      final sell = _orders[fill.sellOrderId]!;
      if (buy.side != TxSide.buy || sell.side != TxSide.sell ||
          buy.symbol != fill.symbol || sell.symbol != fill.symbol ||
          buy.ownerId == sell.ownerId) {
        throw StateError('Fill order mismatch');
      }
      final linked = _ledger.where((l) => l.fillId == fill.id).toList();
      if (linked.length != 2 ||
          linked.fold<int>(0, (v, l) => v + l.cashDeltaCents) != 0 ||
          linked.fold<int>(0, (v, l) => v + l.shareDelta) != 0) {
        throw StateError('Fill has unbalanced ledger');
      }
    }
    if (_nextFillSequence <= lastFillSeq) throw StateError('Fill sequence rewind');
  }
}

Map<String, int> _intMap(Object? raw) {
  final m = Map<String, dynamic>.from(raw as Map);
  return m.map((k, v) => MapEntry(k, v as int));
}
