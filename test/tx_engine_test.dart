import 'package:flutter_test/flutter_test.dart';

// Relative import avoids assuming the current project's pubspec package name.
import '../lib/engine/tx_engine.dart';

void main() {
  group('V0.1b price-time matching and finite depth', () {
    test('price priority, then FIFO, and multi-level market slippage', () {
      final e = TxEngine()
        ..registerAccount('trader', cashCents: 100000)
        ..registerAccount('mm1', cashCents: 0, shares: {'HIGH': 10})
        ..registerAccount('mm2', cashCents: 0, shares: {'HIGH': 10})
        ..registerAccount('mm3', cashCents: 0, shares: {'HIGH': 10});
      e.place(id: 'ask3', ownerId: 'mm3', symbol: 'HIGH', side: TxSide.sell,
          kind: TxKind.limit, quantity: 10, limitPriceCents: 1100);
      e.place(id: 'ask1', ownerId: 'mm1', symbol: 'HIGH', side: TxSide.sell,
          kind: TxKind.limit, quantity: 10, limitPriceCents: 1000);
      e.place(id: 'ask2', ownerId: 'mm2', symbol: 'HIGH', side: TxSide.sell,
          kind: TxKind.limit, quantity: 10, limitPriceCents: 1000);
      expect(e.depth('HIGH', TxSide.sell).map((v) => v.quantity).toList(), [20, 10]);
      final result = e.place(id: 'take25', ownerId: 'trader', symbol: 'HIGH',
          side: TxSide.buy, kind: TxKind.market, quantity: 25);
      expect(result.status, TxStatus.filled);
      expect(e.fills.map((f) => f.sellOrderId).toList(), ['ask1', 'ask2', 'ask3']);
      expect(e.fills.map((f) => f.priceCents).toList(), [1000, 1000, 1100]);
      expect(e.fills.map((f) => f.quantity).toList(), [10, 10, 5]);
      expect(e.account('trader').cashCents, 74500);
      expect(e.account('trader').sharesOf('HIGH'), 25);
      expect(e.depth('HIGH', TxSide.sell).single.quantity, 5);
      e.checkInvariants();
    });

    test('no infinite liquidity: market remainder cancels', () {
      final e = TxEngine()
        ..registerAccount('buyer', cashCents: 100000)
        ..registerAccount('provider', cashCents: 0, shares: {'LOW': 2});
      e.place(id: 'ask', ownerId: 'provider', symbol: 'LOW', side: TxSide.sell,
          kind: TxKind.limit, quantity: 2, limitPriceCents: 300);
      final o = e.place(id: 'buy5', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.market, quantity: 5);
      expect(o.filled, 2);
      expect(o.remaining, 3);
      expect(o.status, TxStatus.cancelled);
      expect(e.fills.length, 1);
      expect(e.depth('LOW', TxSide.sell), isEmpty);
    });
  });

  group('V0.1b reservations and account consistency', () {
    test('buyer reserves limit notional, price improvement, then cancellation releases', () {
      final e = TxEngine()
        ..registerAccount('buyer', cashCents: 50000)
        ..registerAccount('seller', cashCents: 0, shares: {'HIGH': 6});
      e.place(id: 's', ownerId: 'seller', symbol: 'HIGH', side: TxSide.sell,
          kind: TxKind.limit, quantity: 6, limitPriceCents: 1000);
      final b = e.place(id: 'b', ownerId: 'buyer', symbol: 'HIGH',
          side: TxSide.buy, kind: TxKind.limit, quantity: 10, limitPriceCents: 1200);
      expect(b.status, TxStatus.partiallyFilled);
      expect(b.remaining, 4);
      expect(e.account('buyer').cashCents, 44000);
      expect(e.account('buyer').reservedCashCents, 4800);
      expect(e.account('buyer').availableCashCents, 39200);
      expect(e.account('buyer').sharesOf('HIGH'), 6);
      e.cancel('b', ownerId: 'buyer');
      expect(b.status, TxStatus.cancelled);
      expect(e.account('buyer').reservedCashCents, 0);
      expect(e.account('buyer').cashCents, 44000);
      expect(e.fills.length, 1);
      e.checkInvariants();
    });

    test('reserved holdings prevent overselling and release after partial fill', () {
      final e = TxEngine()
        ..registerAccount('owner', cashCents: 0, shares: {'LOW': 10})
        ..registerAccount('buyer', cashCents: 20000);
      e.place(id: 's8', ownerId: 'owner', symbol: 'LOW', side: TxSide.sell,
          kind: TxKind.limit, quantity: 8, limitPriceCents: 1000);
      expect(e.account('owner').reservedSharesOf('LOW'), 8);
      final rejected = e.place(id: 's3', ownerId: 'owner', symbol: 'LOW',
          side: TxSide.sell, kind: TxKind.limit, quantity: 3, limitPriceCents: 1100);
      expect(rejected.status, TxStatus.rejected);
      expect(rejected.rejectReason, contains('Insufficient'));
      e.place(id: 'b5', ownerId: 'buyer', symbol: 'LOW', side: TxSide.buy,
          kind: TxKind.market, quantity: 5);
      expect(e.account('owner').sharesOf('LOW'), 5);
      expect(e.account('owner').reservedSharesOf('LOW'), 3);
      expect(e.account('owner').cashCents, 5000);
      e.cancel('s8', ownerId: 'owner');
      expect(e.account('owner').availableSharesOf('LOW'), 5);
      e.checkInvariants();
    });

    test('insufficient market cash rejects all before matching any level', () {
      final e = TxEngine()
        ..registerAccount('buyer', cashCents: 1000)
        ..registerAccount('seller', cashCents: 0, shares: {'HIGH': 3});
      e.place(id: 's', ownerId: 'seller', symbol: 'HIGH', side: TxSide.sell,
          kind: TxKind.limit, quantity: 3, limitPriceCents: 500);
      final b = e.place(id: 'b', ownerId: 'buyer', symbol: 'HIGH',
          side: TxSide.buy, kind: TxKind.market, quantity: 3);
      expect(b.status, TxStatus.rejected);
      expect(e.fills, isEmpty);
      expect(e.depth('HIGH', TxSide.sell).single.quantity, 3);
      expect(e.account('buyer').cashCents, 1000);
      e.checkInvariants();
    });

    test('cancel ownership and idempotent order submission', () {
      final e = TxEngine()
        ..registerAccount('buyer', cashCents: 2000)
        ..registerAccount('seller', cashCents: 0, shares: {'LOW': 2});
      e.place(id: 's', ownerId: 'seller', symbol: 'LOW', side: TxSide.sell,
          kind: TxKind.limit, quantity: 2, limitPriceCents: 100);
      final b = e.place(id: 'b', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.market, quantity: 2);
      final repeat = e.place(id: 'b', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.market, quantity: 2);
      expect(identical(b, repeat), isTrue);
      expect(e.fills.length, 1);
      expect(() => e.place(id: 'b', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.market, quantity: 1), throwsStateError);
      expect(() => e.cancel('s', ownerId: 'buyer'), throwsStateError);
      expect(() => e.cancel('s', ownerId: 'seller'), throwsStateError);
      e.checkInvariants();
    });

    test('invalid quantity and invalid limit price produce rejected orders', () {
      final e = TxEngine()..registerAccount('buyer', cashCents: 2000);
      final zero = e.place(id: 'zero', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.market, quantity: 0);
      final badPrice = e.place(id: 'price', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.limit, quantity: 1, limitPriceCents: -1);
      expect(zero.status, TxStatus.rejected);
      expect(badPrice.status, TxStatus.rejected);
      expect(e.fills, isEmpty);
      e.checkInvariants();
    });

    test('self-trading rejected rather than fabricating volume', () {
      final e = TxEngine()
        ..registerAccount('self', cashCents: 10000, shares: {'LOW': 10});
      e.place(id: 'ask', ownerId: 'self', symbol: 'LOW', side: TxSide.sell,
          kind: TxKind.limit, quantity: 5, limitPriceCents: 100);
      final b = e.place(id: 'bid', ownerId: 'self', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.limit, quantity: 5, limitPriceCents: 100);
      expect(b.status, TxStatus.rejected);
      expect(e.fills, isEmpty);
      expect(e.account('self').reservedCashCents, 0);
      e.checkInvariants();
    });
  });

  group('V0.1b snapshot round trip', () {
    test('recovery preserves partial orders, reservations, ledger and sequence', () {
      final original = TxEngine()
        ..registerAccount('buyer', cashCents: 10000)
        ..registerAccount('seller', cashCents: 0, shares: {'LOW': 6});
      original.place(id: 'bid', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.limit, quantity: 5, limitPriceCents: 1000);
      original.place(id: 'ask', ownerId: 'seller', symbol: 'LOW',
          side: TxSide.sell, kind: TxKind.limit, quantity: 3, limitPriceCents: 900);
      final snapshot = original.exportJson();
      final restored = TxEngine.importJson(snapshot);
      expect(restored.exportJson(), snapshot);
      expect(restored.order('bid').remaining, 2);
      expect(restored.account('buyer').reservedCashCents, 2000);
      expect(restored.account('seller').cashCents, 3000); // maker bid at 1000
      restored.cancel('bid', ownerId: 'buyer');
      expect(restored.account('buyer').reservedCashCents, 0);
      expect(restored.fills.single.priceCents, 1000);
      restored.place(id: 'ask2', ownerId: 'seller', symbol: 'LOW',
          side: TxSide.sell, kind: TxKind.limit, quantity: 3, limitPriceCents: 1100);
      expect(restored.order('ask2').sequence, 3);
      restored.checkInvariants();
    });

    test('restored snapshot rejects altered reservation balances', () {
      final e = TxEngine()..registerAccount('buyer', cashCents: 5000);
      e.place(id: 'bid', ownerId: 'buyer', symbol: 'LOW',
          side: TxSide.buy, kind: TxKind.limit, quantity: 2, limitPriceCents: 1000);
      final altered = e.exportJson().replaceFirst(
          '"reservedCashCents":2000', '"reservedCashCents":0');
      expect(() => TxEngine.importJson(altered), throwsStateError);
    });

    test('unknown snapshot version rejected', () {
      expect(() => TxEngine.importJson('{"version":999}'), throwsFormatException);
    });
  });
}
