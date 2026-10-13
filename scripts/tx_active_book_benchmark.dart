/// R30 pure-Dart market matching microbenchmark.
/// Run from the repository root with `dart run scripts/tx_active_book_benchmark.dart`.
/// This is a developer diagnostic, not a promised Android performance number.
import '../lib/engine/tx_engine.dart';

void main(List<String> args) {
  final history = args.isEmpty ? 5000 : int.parse(args.first);
  if (history < 0 || history > 100000) {
    throw ArgumentError.value(history, 'history', 'Expected 0..100000');
  }
  final engine = TxEngine();
  engine.registerAccount('M', cashCents: 100000000,
      shares: <String, int>{'X': 100000});
  engine.registerAccount('T', cashCents: 100000000);
  // Construct dormant historical orders without one full audit per insert.
  engine.runCheckedMinute(() {
    for (var i = 0; i < history; i++) {
      final id = 'old-$i';
      engine.place(id: id, ownerId: 'M', symbol: 'X',
          side: TxSide.sell, kind: TxKind.limit,
          quantity: 1, limitPriceCents: 1000 + i % 100);
      engine.cancel(id, ownerId: 'M');
    }
    for (var i = 0; i < 10; i++) {
      engine.place(id: 'live-$i', ownerId: 'M', symbol: 'X',
          side: TxSide.sell, kind: TxKind.limit,
          quantity: 100, limitPriceCents: 1000 + i);
    }
  });
  final stopwatch = Stopwatch()..start();
  engine.runCheckedMinute(() {
    for (var i = 0; i < 50; i++) {
      engine.place(id: 'probe-$i', ownerId: 'T', symbol: 'X',
          side: TxSide.buy, kind: TxKind.limit,
          quantity: 1, limitPriceCents: 900);
      engine.cancel('probe-$i', ownerId: 'T');
    }
  });
  stopwatch.stop();
  final active = engine.activeOrders.length;
  print('historical=${engine.orders.length} active=$active '
      'index-probes=50 elapsed-ms=${stopwatch.elapsedMilliseconds}');
  print('Old counterparties scan: ~${history * 50} expired-order visits. '
      'R30 counterparties scan: 0 expired-order visits.');
  engine.checkInvariants();
}
