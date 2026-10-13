/// Read-only trading journal from verified actual fills. No phantom trades.
/// When historical inventory cannot be reconstructed, cost P&L is unknown.
import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';

class TxJournalClose {
  const TxJournalClose({required this.fillId, required this.symbol,
    required this.quantity, required this.proceedsCents,
    required this.realizedCents});
  final String fillId;
  final String symbol;
  final int quantity;
  final int proceedsCents;
  final int realizedCents;
}

class TxJournalSymbol {
  const TxJournalSymbol({required this.symbol, required this.costKnown,
    required this.remainingShares, required this.closedFills,
    required this.winningCloses, required this.losingCloses,
    required this.realizedCents});
  final String symbol;
  final bool costKnown;
  final int remainingShares;
  final int closedFills;
  final int winningCloses;
  final int losingCloses;
  final int realizedCents;
}

class TxTradeJournal {
  const TxTradeJournal._({required this.buyFills, required this.sellFills,
    required this.boughtShares, required this.soldShares,
    required this.buyNotionalCents, required this.sellNotionalCents,
    required this.costKnown, required this.realizedCents,
    required this.closedFills, required this.winningCloses,
    required this.losingCloses, required this.bySymbol,
    required this.recentCloses});
  final int buyFills, sellFills, boughtShares, soldShares;
  final int buyNotionalCents, sellNotionalCents;
  final bool costKnown;
  final int? realizedCents;
  final int closedFills, winningCloses, losingCloses;
  final Map<String,TxJournalSymbol> bySymbol;
  final List<TxJournalClose> recentCloses;
  double? get winRate => !costKnown || closedFills == 0 ? null :
      winningCloses / closedFills;

  /// O(fills + symbols), single pass, bounded last-20 closure history.
  /// Moving weighted-average cost matches TxPositionAnalytics.
  static TxTradeJournal compute(TxSession session) {
    final accounts = <String,_Lot>{
      for (final symbol in TxSession.symbols) symbol: _Lot()
    };
    var buyFills=0, sellFills=0, boughtShares=0, soldShares=0;
    var buyNotional=0, sellNotional=0;
    final recent=<TxJournalClose>[];
    for (var index=0;index<session.engine.fillCount;index++) {
      final fill=session.engine.fillAt(index);
      final buyer=session.engine.order(fill.buyOrderId).ownerId;
      final seller=session.engine.order(fill.sellOrderId).ownerId;
      if (buyer!=TxSession.playerId && seller!=TxSession.playerId) continue;
      final lot=accounts[fill.symbol];
      if (lot == null) continue;
      if (buyer==TxSession.playerId) {
        buyFills++; boughtShares+=fill.quantity;
        buyNotional+=fill.notionalCents;
        lot.qty+=fill.quantity;
        lot.basis+=fill.notionalCents;
      } else {
        sellFills++; soldShares+=fill.quantity;
        sellNotional+=fill.notionalCents;
        if (!lot.known || fill.quantity>lot.qty) {
          lot.known=false;
          continue;
        }
        final removed=fill.quantity==lot.qty ? lot.basis :
            (lot.basis*fill.quantity+lot.qty~/2)~/lot.qty;
        lot.qty-=fill.quantity;
        lot.basis-=removed;
        final pnl=fill.notionalCents-removed;
        lot.realized+=pnl;
        lot.closed++;
        if(pnl>0) lot.wins++;
        if(pnl<0) lot.losses++;
        recent.add(TxJournalClose(fillId:fill.id, symbol:fill.symbol,
          quantity:fill.quantity, proceedsCents:fill.notionalCents,
          realizedCents:pnl));
        if (recent.length>20) recent.removeAt(0);
      }
    }
    // Closing with unknown pre-existing shares cannot be assigned a made-up
    // zero cost, even if no fill in the visible history references them.
    final account=session.engine.account(TxSession.playerId);
    for (final symbol in TxSession.symbols) {
      final lot=accounts[symbol]!;
      if (lot.qty!=account.sharesOf(symbol)) lot.known=false;
    }
    final known=accounts.values.every((lot)=>lot.known);
    final perSymbol=<String,TxJournalSymbol>{};
    for (final symbol in TxSession.symbols) {
      final lot=accounts[symbol]!;
      perSymbol[symbol]=TxJournalSymbol(symbol:symbol,
        costKnown:lot.known, remainingShares:account.sharesOf(symbol),
        closedFills:lot.closed, winningCloses:lot.wins,
        losingCloses:lot.losses, realizedCents:lot.realized);
    }
    return TxTradeJournal._(buyFills:buyFills,sellFills:sellFills,
      boughtShares:boughtShares,soldShares:soldShares,
      buyNotionalCents:buyNotional,sellNotionalCents:sellNotional,
      costKnown:known,
      realizedCents:known ? accounts.values.fold<int>(0,(s,l)=>s+l.realized) : null,
      closedFills:accounts.values.fold<int>(0,(s,l)=>s+l.closed),
      winningCloses:accounts.values.fold<int>(0,(s,l)=>s+l.wins),
      losingCloses:accounts.values.fold<int>(0,(s,l)=>s+l.losses),
      bySymbol:Map.unmodifiable(perSymbol),
      recentCloses:List.unmodifiable(recent.reversed));
  }
}

class _Lot {
  int qty=0,basis=0,realized=0,closed=0,wins=0,losses=0;
  bool known=true;
}
