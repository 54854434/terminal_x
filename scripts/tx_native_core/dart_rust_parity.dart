/// Differential replay of the SAME funded command stream in Dart and Rust.
/// Usage after `cargo build --release --locked`:
/// dart run scripts/tx_native_core/dart_rust_parity.dart \
///   scripts/tx_native_core/target/release/libterminal_x_core.so
/// This never opens or touches the user's SQLite database.
import 'dart:ffi' as ffi;
import 'dart:io';

import '../../lib/engine/tx_engine.dart';
import '../../lib/engine/tx_native_core_ffi.dart';

void insist(bool ok, String message) {
  if (!ok) throw StateError('Dart/Rust parity: $message');
}

void compare(TxEngine dart, TxNativeCoreFfi rust) {
  dart.checkInvariants();
  insist(rust.isAudited, 'native audit failed');
  const ids = {'B': 1, 'S': 2, 'T': 3};
  for (final pair in ids.entries) {
    final account = dart.account(pair.key);
    insist(account.cashCents == rust.cashCents(pair.value),
        'cash ${pair.key}');
    insist(account.reservedCashCents == rust.reservedCashCents(pair.value),
        'reserved cash ${pair.key}');
    for (final symbol in [0, 1, 99]) {
      final name = symbol == 0 ? 'SIM-A01' :
          symbol == 1 ? 'SIM-A02' : 'SIM-A99';
      insist(account.sharesOf(name) == rust.shares(pair.value, symbol),
          'shares ${pair.key}/$name');
      insist(account.reservedSharesOf(name) ==
          rust.reservedShares(pair.value, symbol),
          'reserved shares ${pair.key}/$name');
    }
  }
  var resting = 0;
  for (final order in dart.orders.values) {
    final id = int.parse(order.id.substring(1));
    insist(order.remaining == rust.remaining(id), 'remaining ${order.id}');
    insist(order.status.index == rust.orderStatus(id),
        'status ${order.id}');
    if (order.kind == TxKind.limit && order.remaining > 0 &&
        (order.status == TxStatus.open ||
         order.status == TxStatus.partiallyFilled)) resting++;
  }
  insist(resting == rust.activeOrderCount, 'resting book count');
  insist(dart.fills.length == rust.fillCount, 'real fill count');
  for (var i = 0; i < dart.fills.length; i++) {
    final fill = dart.fills[i];
    insist(fill.priceCents == rust.fillPrice(i), 'fill price $i');
    insist(fill.quantity == rust.fillQuantity(i), 'fill quantity $i');
  }
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Expected path to compiled libterminal_x_core.so');
    exitCode = 2;
    return;
  }
  final rust = TxNativeCoreFfi.open(ffi.DynamicLibrary.open(args.single));
  try {
    final dart = TxEngine();
    for (final (id, cash, a, b) in [
      (1, 100000, 0, 0),
      (2, 1000, 100, 30),
      (3, 3000, 50, 30),
    ]) {
      final owner = switch (id) { 1 => 'B', 2 => 'S', _ => 'T' };
      dart.registerAccount(owner, cashCents: cash, shares: {
        'SIM-A01': a, 'SIM-A02': b,
      });
      insist(rust.registerAccount(id: id, cashCents: cash,
          simA01Shares: a, simA02Shares: b) == 0, 'register $owner');
    }
    compare(dart, rust);

    void place(int id, int owner, int symbol, TxSide side, TxKind kind,
        int qty, int price) {
      final player = switch (owner) { 1 => 'B', 2 => 'S', _ => 'T' };
      final sym = symbol == 0 ? 'SIM-A01' :
          symbol == 1 ? 'SIM-A02' : 'SIM-A99';
      final order = dart.place(id: 'O$id', ownerId: player,
          symbol: sym, side: side, kind: kind, quantity: qty,
          limitPriceCents: kind == TxKind.limit ? price : null);
      final result = rust.place(orderId: id, ownerId: owner, symbol: symbol,
          side: side.index, kind: kind.index, quantity: qty,
          priceCents: price);
      insist(order.status.index == result, 'place $id returned $result vs ${order.status}');
      compare(dart, rust);
    }

    void cancel(int id, int owner) {
      final player = switch (owner) { 1 => 'B', 2 => 'S', _ => 'T' };
      final order = dart.cancel('O$id', ownerId: player);
      final status = rust.cancel(orderId: id, ownerId: owner);
      insist(order.status.index == status, 'cancel $id');
      compare(dart, rust);
    }

    place(10, 1, 0, TxSide.buy, TxKind.limit, 10, 100);
    place(11, 2, 0, TxSide.sell, TxKind.limit, 4, 100);
    cancel(10, 1);
    place(12, 2, 0, TxSide.sell, TxKind.limit, 5, 103);
    place(13, 3, 0, TxSide.sell, TxKind.limit, 5, 102);
    place(14, 1, 0, TxSide.buy, TxKind.market, 7, 0);
    place(15, 1, 1, TxSide.buy, TxKind.limit, 5, 300);
    place(16, 2, 1, TxSide.sell, TxKind.limit, 3, 299);
    cancel(15, 1);
    // New symbols are extensible, but opening holdings must be registered
    // before orders; all three accounts currently hold zero SIM-A99 shares.
    place(17, 1, 99, TxSide.buy, TxKind.market, 2, 0);
    compare(dart, rust);

    final rebuilt = rust.rebuildFromEvents();
    try {
      compare(dart, rebuilt);
      insist(rebuilt.eventCount == rust.eventCount,
          'rebuild event count');
      for (var i = 0; i < rust.eventCount; i++) {
        final a = rust.eventAt(i);
        final b = rebuilt.eventAt(i);
        insist(a.action == b.action && a.orderId == b.orderId &&
            a.ownerId == b.ownerId && a.symbol == b.symbol &&
            a.quantity == b.quantity &&
            a.expectedResult == b.expectedResult,
            'event mismatch $i');
      }
    } finally { rebuilt.close(); }
    stdout.writeln('Dart/Rust deterministic funded-stream parity PASS; '
        '${rust.eventCount} events; ${rust.fillCount} real fills.');
  } finally { rust.close(); }
}
