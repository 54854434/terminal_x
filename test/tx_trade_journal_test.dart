import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_trade_journal.dart';

void main() {
  test('empty journal has no invented trades, cost is known',(){
    final s=TxSession.fresh();
    final j=TxTradeJournal.compute(s);
    expect(j.buyFills,0);expect(j.sellFills,0);
    expect(j.realizedCents,0);expect(j.winRate,isNull);
    expect(j.recentCloses,isEmpty);
  });
  test('buy and partial sale produce a matched close without mutation',(){
    final s=TxSession.fresh();
    s.placePlayer(symbol:TxSession.symbols[0],side:TxSide.buy,
      kind:TxKind.market,quantity:100);
    s.placePlayer(symbol:TxSession.symbols[0],side:TxSide.sell,
      kind:TxKind.market,quantity:50);
    final snapshot=s.exportJson();
    final j=TxTradeJournal.compute(s);
    expect(j.boughtShares,100);expect(j.soldShares,50);
    expect(j.costKnown,isTrue);
    expect(j.closedFills,1);expect(j.recentCloses.length,1);
    final executions=s.engine.fills;
    expect(j.realizedCents,
      executions[1].notionalCents-executions[0].notionalCents~/2);
    expect(s.exportJson(),snapshot);
  });
  test('ledger journal is restored identically from JSON',(){
    final s=TxSession.fresh();
    s.placePlayer(symbol:TxSession.symbols[0],side:TxSide.buy,
      kind:TxKind.market,quantity:100);
    final a=TxTradeJournal.compute(s);
    final b=TxTradeJournal.compute(TxSession.importJson(s.exportJson()));
    expect(a.boughtShares,b.boughtShares);
    expect(a.realizedCents,b.realizedCents);
    expect(a.bySymbol.keys,b.bySymbol.keys);
  });
  test('legacy beginning inventory is marked cost unknown',(){
    final s=TxSession.fromLegacyJson('{"cash":1000.0,"prices":[10.0,25.0],'
      '"owned":[100,0],"step":0,"pending":[],"trades":[]}');
    final j=TxTradeJournal.compute(s);
    expect(j.costKnown,isFalse);expect(j.realizedCents,isNull);
    expect(j.winRate,isNull);
  });
}
