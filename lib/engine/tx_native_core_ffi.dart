/// R36: opt-in ABI bridge for the future Rust matching backend.
///
/// No import or automatic initialization is performed by the production
/// trading service. An unavailable native library MUST NOT alter accounts,
/// commits, clock, or current Dart engine behavior.
///
/// The exported C ABI uses integer cents, quantities and stable numeric ids.
/// The real app's STRING account/order identifiers must be mapped by a
/// versioned persistent adapter before this can replace TxEngine.
import 'dart:ffi' as ffi;

/// Reproducible, future-proof event payload from the Rust core.
/// Native pointers are never held by this Dart record.
class TxNativeEvent {
  const TxNativeEvent({required this.action, required this.ownerId,
      required this.orderId, required this.symbol, required this.side,
      required this.orderKind, required this.quantity,
      required this.priceCents, required this.cashCents,
      required this.sharesA, required this.sharesB,
      required this.expectedResult});
  final int action, ownerId, orderId, symbol, side, orderKind;
  final int quantity, priceCents, cashCents, sharesA, sharesB, expectedResult;
}

final class _TxNativeEventStruct extends ffi.Struct {
  @ffi.Uint32()
  external int action;
  @ffi.Uint32()
  external int side;
  @ffi.Uint32()
  external int orderKind;
  @ffi.Uint32()
  external int symbol;
  @ffi.Uint64()
  external int orderId;
  @ffi.Uint64()
  external int ownerId;
  @ffi.Int64()
  external int quantity;
  @ffi.Int64()
  external int priceCents;
  @ffi.Int64()
  external int cashCents;
  @ffi.Int64()
  external int sharesA;
  @ffi.Int64()
  external int sharesB;
  @ffi.Int32()
  external int expectedResult;
  @ffi.Int32()
  external int reserved;
}

class TxNativeCoreFfi {
  TxNativeCoreFfi._(this._library, this._engine);

  static const int requiredAbiVersion = 2;
  static const int buy = 0;
  static const int sell = 1;
  static const int limit = 0;
  static const int market = 1;
  static const int open = 0;
  static const int partial = 1;
  static const int filled = 2;
  static const int cancelled = 3;
  static const int rejected = 4;
  static const int symbolA01 = 0;
  static const int symbolA02 = 1;

  final ffi.DynamicLibrary _library;
  ffi.Pointer<ffi.Void> _engine;

  /// Dynamically loads an already-built library. This does not build or
  /// extract an Android .so; the current ZIP importer has no Rust NDK step.
  /// The production trading service intentionally does not call this method.
  static TxNativeCoreFfi open(ffi.DynamicLibrary library) {
    final version = library.lookupFunction<ffi.Uint32 Function(),
        int Function()>('tx_core_abi_version')();
    if (version != requiredAbiVersion) {
      throw StateError('Unsupported Terminal X native core ABI: $version');
    }
    final create = library.lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()>('tx_core_new');
    final engine = create();
    if (engine == ffi.nullptr) {
      throw StateError('Unable to allocate native market state');
    }
    return TxNativeCoreFfi._(library, engine);
  }

  /// Deliberately explicit: do not silently enable a different engine when a
  /// device happens to contain another library with the same filename.
  static TxNativeCoreFfi openInstalledAndroidLibrary() =>
      open(ffi.DynamicLibrary.open('libterminal_x_core.so'));

  void _ensureOpen() {
    if (_engine == ffi.nullptr) {
      throw StateError('Native core has been disposed');
    }
  }

  int registerAccount({required int id, required int cashCents,
      required int simA01Shares, required int simA02Shares}) {
    _ensureOpen();
    final register = _library.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Int64,
            ffi.Int64, ffi.Int64),
        int Function(ffi.Pointer<ffi.Void>, int, int, int, int)>(
        'tx_core_register');
    return register(_engine, id, cashCents, simA01Shares, simA02Shares);
  }

  /// Register a future symbol's initial inventory (before the first order).
  int addInitialShares({required int ownerId, required int symbol,
      required int quantity}) {
    _ensureOpen();
    final add = _library.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64,
            ffi.Uint32, ffi.Int64),
        int Function(ffi.Pointer<ffi.Void>, int, int, int)>(
        'tx_core_add_initial_shares');
    return add(_engine, ownerId, symbol, quantity);
  }

  int place({required int orderId, required int ownerId,
      required int symbol, required int side, required int kind,
      required int quantity, required int priceCents}) {
    _ensureOpen();
    final place = _library.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Uint64,
            ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Int64, ffi.Int64),
        int Function(ffi.Pointer<ffi.Void>, int, int,
            int, int, int, int, int)>('tx_core_place');
    return place(_engine, orderId, ownerId, symbol, side, kind, quantity,
        priceCents);
  }

  int cancel({required int orderId, required int ownerId}) {
    _ensureOpen();
    final cancel = _library.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Uint64),
        int Function(ffi.Pointer<ffi.Void>, int, int)>('tx_core_cancel');
    return cancel(_engine, orderId, ownerId);
  }

  int _readOne(String symbol, int value) {
    _ensureOpen();
    final getter = _library.lookupFunction<
        ffi.Int64 Function(ffi.Pointer<ffi.Void>, ffi.Uint64),
        int Function(ffi.Pointer<ffi.Void>, int)>(symbol);
    return getter(_engine, value);
  }

  int _readTwo(String symbol, int id, int symbolIndex) {
    _ensureOpen();
    final getter = _library.lookupFunction<
        ffi.Int64 Function(ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Uint32),
        int Function(ffi.Pointer<ffi.Void>, int, int)>(symbol);
    return getter(_engine, id, symbolIndex);
  }

  int cashCents(int id) => _readOne('tx_core_cash', id);
  int reservedCashCents(int id) => _readOne('tx_core_reserved_cash', id);
  int shares(int id, int symbol) => _readTwo('tx_core_shares', id, symbol);
  int reservedShares(int id, int symbol) =>
      _readTwo('tx_core_reserved_shares', id, symbol);
  int remaining(int orderId) => _readOne('tx_core_order_remaining', orderId);

  int get fillCount {
    _ensureOpen();
    final getter = _library.lookupFunction<
        ffi.Int64 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('tx_core_fill_count');
    return getter(_engine);
  }

  int fillPrice(int index) => _readOne('tx_core_fill_price', index);
  int fillQuantity(int index) => _readOne('tx_core_fill_quantity', index);

  int get eventCount {
    _ensureOpen();
    final count = _library.lookupFunction<
        ffi.Uint64 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('tx_core_event_count');
    return count(_engine);
  }

  /// Copies native event fields immediately; no borrowed Rust pointers escape.
  TxNativeEvent eventAt(int index) {
    _ensureOpen();
    if (index < 0 || index >= eventCount) {
      throw RangeError.range(index, 0, eventCount - 1, 'index');
    }
    final read = _library.lookupFunction<
        ffi.Pointer<_TxNativeEventStruct> Function(
            ffi.Pointer<ffi.Void>, ffi.Uint64),
        ffi.Pointer<_TxNativeEventStruct> Function(
            ffi.Pointer<ffi.Void>, int)>('tx_core_event_at');
    final p = read(_engine, index);
    if (p == ffi.nullptr) throw StateError('Native event missing');
    final row = p.ref;
    if (row.reserved != 0) throw StateError('Native event ABI corruption');
    return TxNativeEvent(
      action: row.action, side: row.side, orderKind: row.orderKind,
      symbol: row.symbol, orderId: row.orderId, ownerId: row.ownerId,
      quantity: row.quantity, priceCents: row.priceCents,
      cashCents: row.cashCents, sharesA: row.sharesA,
      sharesB: row.sharesB, expectedResult: row.expectedResult,
    );
  }

  int orderStatus(int id) {
    _ensureOpen();
    final getter = _library.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64),
        int Function(ffi.Pointer<ffi.Void>, int)>('tx_core_order_status');
    return getter(_engine, id);
  }

  int get activeOrderCount {
    _ensureOpen();
    final getter = _library.lookupFunction<
        ffi.Uint64 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('tx_core_active_order_count');
    return getter(_engine);
  }

  /// Creates a fresh native engine by replaying its journal. Returns an
  /// independent handle or throws; never mutates the running engine.
  TxNativeCoreFfi rebuildFromEvents() {
    _ensureOpen();
    final rebuild = _library.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
        'tx_core_rebuild_from_events');
    final ptr = rebuild(_engine);
    if (ptr == ffi.nullptr) throw StateError('Native journal replay failed');
    return TxNativeCoreFfi._(_library, ptr);
  }

  bool get isAudited {
    _ensureOpen();
    final verify = _library.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)>('tx_core_verify');
    return verify(_engine) == 1;
  }

  /// Exactly-once ownership. A disposed handle cannot be reused or sent to
  /// another Isolate; each Isolate must create its own library handle.
  void close() {
    if (_engine == ffi.nullptr) return;
    final free = _library.lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)>('tx_core_free');
    final pointer = _engine;
    _engine = ffi.nullptr;
    free(pointer);
  }
}
