import 'package:flutter_test/flutter_test.dart';

import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_execution_estimate.dart';
import '../lib/market/tx_npc_market.dart';

void main() {
  test('read-only market sweep reconciles with real FIFO fills and VWAP', () {
    final session = TxSession.fresh();
    final before = session.exportJson();
    final quote = TxExecutionEstimate.estimate(session.engine,
        ownerId: TxSession.playerId, symbol: 'SIM-A01',
        side: TxSide.buy, quantity: 200);
    expect(quote.rejected, isFalse);
    expect(quote.executableShares, 200);
    expect(quote.unfilledShares, 0);
    expect(quote.bestPriceCents, 1001);
    expect(quote.worstPriceCents, 1002);
    expect(quote.notionalCents, 100 * 1001 + 100 * 1002);
    expect(quote.vwapCents, 1001.5);
    expect(quote.slippageCentsPerShare, 0.5);
    expect(session.exportJson(), before, reason: 'estimate must not mutate');

    final actual = session.placePlayer(symbol: 'SIM-A01',
        side: TxSide.buy, kind: TxKind.market, quantity: 200);
    expect(actual.status, TxStatus.filled);
    expect(session.engine.fills.fold<int>(0,
        (sum, fill) => sum + fill.notionalCents), quote.notionalCents);
    session.engine.checkInvariants();
  });

  test('large order sees bounded book rather than fabricated liquidity', () {
    final session = TxSession.fresh();
    final quote = TxExecutionEstimate.estimate(session.engine,
        ownerId: TxSession.playerId, symbol: 'SIM-A01',
        side: TxSide.buy, quantity: 10000);
    expect(quote.rejected, isFalse);
    expect(quote.executableShares, 1650);
    expect(quote.unfilledShares, 8350);
    final actual = session.placePlayer(symbol: 'SIM-A01',
        side: TxSide.buy, kind: TxKind.market, quantity: 10000);
    expect(actual.status, TxStatus.cancelled);
    expect(actual.filled, quote.executableShares);
    expect(session.engine.fills.fold<int>(0,
        (sum, fill) => sum + fill.notionalCents), quote.notionalCents);
  });

  test('cash shortfall and self crossing fail closed before fake fills', () {
    final engine = TxEngine();
    engine.registerAccount('BUYER', cashCents: 1000);
    engine.registerAccount('SELLER', cashCents: 10000, shares: {'S': 10});
    engine.place(id: 'ASK1', ownerId: 'SELLER', symbol: 'S',
        side: TxSide.sell, kind: TxKind.limit,
        quantity: 10, limitPriceCents: 200);
    final cost = TxExecutionEstimate.estimate(engine,
        ownerId: 'BUYER', symbol: 'S', side: TxSide.buy, quantity: 10);
    expect(cost.rejected, isTrue);
    expect(cost.rejectReason, 'Insufficient available cash');
    expect(cost.executableShares, 0);
    expect(engine.fills, isEmpty);

    final own = TxEngine();
    own.registerAccount('A', cashCents: 100000, shares: {'S': 10});
    own.place(id: 'OWN-ASK', ownerId: 'A', symbol: 'S',
        side: TxSide.sell, kind: TxKind.limit,
        quantity: 10, limitPriceCents: 200);
    final self = TxExecutionEstimate.estimate(own,
        ownerId: 'A', symbol: 'S', side: TxSide.buy, quantity: 5);
    expect(self.rejectReason, 'Self-trade prevention');
    expect(self.executableShares, 0);
    own.checkInvariants();
  });

  test('NPC risk-adjusted book stays deterministic after snapshot restore', () {
    final a = TxSession.freshWithAgents();
    final b = TxSession.importJson(a.exportJson());
    for (var i = 0; i < 8; i++) {
      a.nextTick();
      b.nextTick();
      expect(a.exportJson(), b.exportJson());
      expect(TxNpcMarket.isEnabled(a.engine), isTrue);
      for (final id in TxNpcMarket.participants) {
        final account = a.engine.account(id);
        expect(account.availableCashCents, greaterThanOrEqualTo(0));
        for (final symbol in TxSession.symbols) {
          expect(account.availableSharesOf(symbol), greaterThanOrEqualTo(0));
        }
      }
    }
    expect(a.engine.fills, isNotEmpty);
    a.engine.checkInvariants();
  });
}
