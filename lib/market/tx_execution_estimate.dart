/// Read-only, maker-price market sweep. This is an executable book estimate,
/// not a quote, fill, ledger mutation, or promise of future liquidity.
///
/// Mirrors TxEngine.place's market-order preflight (price/FIFO, self-trade,
/// available cash, whole sell quantity). No real order is submitted.
import '../engine/tx_engine.dart';

class TxExecutionEstimate {
  const TxExecutionEstimate({
    required this.side,
    required this.requestedShares,
    required this.executableShares,
    required this.notionalCents,
    required this.bestPriceCents,
    required this.worstPriceCents,
    required this.levelsConsumed,
    required this.rejectReason,
  });

  final TxSide side;
  final int requestedShares;
  final int executableShares;
  final int notionalCents;
  final int? bestPriceCents;
  final int? worstPriceCents;
  final int levelsConsumed;
  final String? rejectReason;

  bool get rejected => rejectReason != null;
  int get unfilledShares => requestedShares - executableShares;
  double? get vwapCents => executableShares == 0
      ? null : notionalCents / executableShares;
  double? get slippageCentsPerShare {
    if (bestPriceCents == null || executableShares == 0) return null;
    return (side == TxSide.buy
        ? notionalCents - executableShares * bestPriceCents!
        : executableShares * bestPriceCents! - notionalCents) /
        executableShares;
  }

  static TxExecutionEstimate estimate(
    TxEngine engine, {
    required String ownerId,
    required String symbol,
    required TxSide side,
    required int quantity,
  }) {
    if (quantity <= 0 || quantity > TxEngine.maxQuantity || symbol.isEmpty) {
      throw ArgumentError('Invalid market order quantity or symbol');
    }
    final owner = engine.account(ownerId);
    final sellers = side == TxSide.buy;
    // The engine's active-order index already excludes filled/cancelled
    // history. A ticket preview must not become O(history) after a long game.
    final makers = engine.activeOrders.where((o) =>
        o.symbol == symbol && o.side != side).toList()
      ..sort((a, b) {
        final price = sellers
            ? a.limitPriceCents!.compareTo(b.limitPriceCents!)
            : b.limitPriceCents!.compareTo(a.limitPriceCents!);
        return price != 0 ? price : a.sequence.compareTo(b.sequence);
      });

    var remaining = quantity;
    var notional = 0;
    var filled = 0;
    var levelsConsumed = 0;
    int? best;
    int? worst;
    for (final maker in makers) {
      if (remaining == 0) break;
      // The engine rejects self-crosses encountered during its preflight.
      if (maker.ownerId == ownerId) {
        return _rejected(quantity, side, 'Self-trade prevention');
      }
      final take = remaining < maker.remaining ? remaining : maker.remaining;
      final price = maker.limitPriceCents!;
      notional += take * price;
      if (notional > TxEngine.maxNotionalCents) {
        return _rejected(quantity, side, 'Market order notional exceeds limit');
      }
      best ??= price;
      worst = price;
      filled += take;
      if (take > 0) levelsConsumed++;
      remaining -= take;
    }
    if (side == TxSide.buy && notional > owner.availableCashCents) {
      return _rejected(quantity, side, 'Insufficient available cash');
    }
    if (side == TxSide.sell && quantity > owner.availableSharesOf(symbol)) {
      return _rejected(quantity, side, 'Insufficient available shares');
    }
    return TxExecutionEstimate(
      requestedShares: quantity, executableShares: filled,
      notionalCents: notional, bestPriceCents: best,
      worstPriceCents: worst, rejectReason: null,
      levelsConsumed: levelsConsumed,
      side: side,
    );
  }

  static TxExecutionEstimate _rejected(int requested, TxSide side, String reason) =>
      TxExecutionEstimate(side: side, requestedShares: requested, executableShares: 0,
          notionalCents: 0, bestPriceCents: null,
          worstPriceCents: null, levelsConsumed: 0, rejectReason: reason);
}
