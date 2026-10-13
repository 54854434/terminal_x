/// Native-first production matching bridge for the Rust game database.
/// The authoritative executable book belongs to Rust; the Dart engine is a
/// projection for existing Flutter screens, candle history and SQLite IO.
/// NO native pointer crosses isolates. The journal can rebuild every action.
import 'tx_engine.dart';
import 'tx_session.dart';
import 'tx_native_core_ffi.dart';

class TxRustMarketGate implements TxEngineNativeGate {
  TxRustMarketGate._(this.session, this.native);
  final TxSession session;
  final TxNativeCoreFfi native;
  final Map<String, int> _accountIds = <String, int>{};
  final Map<String, int> _orderIds = <String, int>{};
  int _nextAccountId = 0;
  int _nextOrderId = 0;
  int _verifiedFillCount = 0;

  /// Compare only live orders, not the unbounded archived order history.
  /// Cash, share reserves and actual fills are audited separately in verify().
  static void verifyRestingParity(TxEngine engine, {
    required int nativeActiveCount,
    required int? Function(String) mapOrderId,
    required int Function(int) remaining,
    required int Function(int) status,
  }) {
    var dartActive = 0;
    for (final order in engine.activeOrders) {
      dartActive++;
      final nativeId = mapOrderId(order.id);
      if (nativeId == null ||
          remaining(nativeId) != order.remaining ||
          status(nativeId) != order.status.index) {
        throw StateError('Rust live order differs: ${order.id}');
      }
    }
    if (dartActive != nativeActiveCount) {
      throw StateError('Rust active order count differs');
    }
  }

  static TxRustMarketGate open(TxSession session) {
    final api = TxNativeCoreFfi.openInstalledAndroidLibrary();
    final gate = TxRustMarketGate._(session, api);
    try {
      if (session.nativeEvents.isEmpty) {
        // New Rust install uses a separate database. Bootstrapping from an
        // arbitrary legacy history is intentionally forbidden.
        if (session.step != 0 || session.engine.fillCount != 0 ||
            session.engine.orders.values.any((o) =>
                o.status != TxStatus.open)) {
          throw StateError('非 Rust 游戏存档无法直接恢复：请清理当前 Rust 游戏数据');
        }
        gate._bootstrapFresh();
      } else {
        gate._restoreJournal();
      }
      gate.verify(session.engine);
      TxEngine.bindNativeGate(session.engine, gate);
      return gate;
    } catch (_) {
      api.close();
      rethrow;
    }
  }

  void _append(List<Object?> event) => session.nativeEvents.add(event);

  void _register(String name, int id, int cash, int a, int b,
      {bool record = true}) {
    if (_accountIds.containsKey(name) || _accountIds.containsValue(id)) {
      throw StateError('Duplicate Rust account ID');
    }
    if (native.registerAccount(id: id, cashCents: cash,
            simA01Shares: a, simA02Shares: b) != 0) {
      throw StateError('Rust account registration rejected: $name');
    }
    _accountIds[name] = id;
    if (id > _nextAccountId) _nextAccountId = id;
    if (record) _append(<Object?>[1, name, id, cash, a, b]);
  }

  int _symbolId(String symbol) {
    final value = TxSession.symbols.indexOf(symbol);
    if (value < 0) throw StateError('Rust unknown symbol: $symbol');
    return value;
  }

  void _placeRaw(String orderId, int id, int owner, int symbol,
      int side, int kind, int quantity, int price, {bool record = true}) {
    if (_orderIds.containsKey(orderId) || _orderIds.containsValue(id)) {
      throw StateError('Duplicate native order mapping: $orderId');
    }
    final code = native.place(orderId: id, ownerId: owner, symbol: symbol,
        side: side, kind: kind, quantity: quantity, priceCents: price);
    if (code < 0) throw StateError('Rust rejected malformed order $orderId: $code');
    _orderIds[orderId] = id;
    if (id > _nextOrderId) _nextOrderId = id;
    if (record) _append(<Object?>[3, orderId, id, owner, symbol,
        side, kind, quantity, price]);
  }

  int _nativeKind(TxKind kind, TxTimeInForce timeInForce) {
    if (kind == TxKind.market) {
      if (timeInForce != TxTimeInForce.gtc) {
        throw ArgumentError('Market orders only support GTC semantics');
      }
      return TxNativeCoreFfi.market;
    }
    return switch (timeInForce) {
      TxTimeInForce.gtc => TxNativeCoreFfi.limit,
      TxTimeInForce.postOnly => TxNativeCoreFfi.postOnly,
      TxTimeInForce.ioc => TxNativeCoreFfi.ioc,
      TxTimeInForce.fok => TxNativeCoreFfi.fok,
    };
  }

  void _cancelRaw(int order, int owner, {bool record = true}) {
    final code = native.cancel(orderId: order, ownerId: owner);
    if (code < 0) throw StateError('Rust cancel failed: $code');
    if (record) _append(<Object?>[4, order, owner]);
  }

  void _bootstrapFresh() {
    for (final account in session.engine.accounts.values) {
      final data = account.toJson();
      final initialShares = Map<String, dynamic>.from(
          data['openingShares'] as Map);
      _register(account.id, ++_nextAccountId,
          data['openingCashCents'] as int,
          (initialShares[TxSession.symbols[0]] as int?) ?? 0,
          (initialShares[TxSession.symbols[1]] as int?) ?? 0);
    }
    final seeded = session.engine.orders.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final order in seeded) {
      _placeRaw(order.id, ++_nextOrderId, _accountIds[order.ownerId]!,
          _symbolId(order.symbol), order.side.index,
          _nativeKind(order.kind, order.timeInForce),
          order.quantity, order.limitPriceCents ?? 0);
    }
  }

  void _restoreJournal() {
    // Replay in chronological mutation order. No fake fills or initial
    // balance corrections: Rust must recreate the exact account state.
    for (final row in session.nativeEvents) {
      if (row.isEmpty || row[0] is! int) {
        throw const FormatException('Malformed Rust replay entry');
      }
      if (row[0] == 1 && row.length == 6) {
        _register(row[1] as String, row[2] as int, row[3] as int,
            row[4] as int, row[5] as int, record: false);
      } else if (row[0] == 3 && row.length == 9) {
        _placeRaw(row[1] as String, row[2] as int, row[3] as int,
            row[4] as int, row[5] as int, row[6] as int,
            row[7] as int, row[8] as int, record: false);
      } else if (row[0] == 4 && row.length == 3) {
        _cancelRaw(row[1] as int, row[2] as int, record: false);
      } else {
        throw const FormatException('Unsupported native replay action');
      }
    }
  }

  @override
  void place(String id, String ownerId, String symbol, TxSide side,
      TxKind kind, int quantity, int? limitPriceCents,
      {TxTimeInForce timeInForce = TxTimeInForce.gtc}) {
    final owner = _accountIds[ownerId];
    if (owner == null) throw StateError('Rust account not found: $ownerId');
    final existing = _orderIds[id];
    if (existing != null) {
      // Native duplicate ID handling is immutable and idempotent.
      final result = native.place(orderId: existing, ownerId: owner,
          symbol: _symbolId(symbol), side: side.index,
          kind: _nativeKind(kind, timeInForce),
          quantity: quantity, priceCents: limitPriceCents ?? 0);
      if (result < 0) throw StateError('Conflicting native retry: $id');
      return;
    }
    _placeRaw(id, _nextOrderId + 1, owner, _symbolId(symbol),
        side.index, _nativeKind(kind, timeInForce), quantity,
        limitPriceCents ?? 0);
  }

  @override
  void cancel(String id, String ownerId) {
    final order = _orderIds[id];
    final owner = _accountIds[ownerId];
    if (order == null || owner == null) {
      throw StateError('Unknown Rust cancellation mapping');
    }
    _cancelRaw(order, owner);
  }

  @override
  void verify(TxEngine engine) {
    if (!native.isAudited || native.fillCount != engine.fillCount) {
      throw StateError('Rust order book or genuine fill count mismatch');
    }
    verifyRestingParity(engine,
        nativeActiveCount: native.activeOrderCount,
        mapOrderId: (id) => _orderIds[id],
        remaining: native.remaining,
        status: native.orderStatus);
    for (final entry in _accountIds.entries) {
      final dart = engine.account(entry.key);
      final id = entry.value;
      if (dart.cashCents != native.cashCents(id) ||
          dart.reservedCashCents != native.reservedCashCents(id)) {
        throw StateError('Rust cash ledger differs for ${entry.key}');
      }
      for (var symbol = 0; symbol < TxSession.symbols.length; symbol++) {
        final name = TxSession.symbols[symbol];
        if (dart.sharesOf(name) != native.shares(id, symbol) ||
            dart.reservedSharesOf(name) != native.reservedShares(id, symbol)) {
          throw StateError('Rust share ledger differs for ${entry.key}/$name');
        }
      }
    }
    for (var i = _verifiedFillCount; i < native.fillCount; i++) {
      final fill = engine.fillAt(i);
      if (fill.quantity != native.fillQuantity(i) ||
          fill.priceCents != native.fillPrice(i) ||
          _orderIds[fill.buyOrderId] != native.fillBuyOrder(i) ||
          _orderIds[fill.sellOrderId] != native.fillSellOrder(i)) {
        throw StateError('Rust confirmed trade differs at fill $i');
      }
    }
    _verifiedFillCount = native.fillCount;
  }

  void close() {
    TxEngine.unbindNativeGate();
    native.close();
  }
}
