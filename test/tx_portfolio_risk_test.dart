import '../lib/market/tx_portfolio_scenarios.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_portfolio_risk.dart';

void main() {
  test('empty holdings produce no phantom exposure or warning', () {
    final session = TxSession.fresh();
    final before = session.exportJson();
    final r = TxPortfolioRisk.compute(session);
    expect(r.investedCents, 0);
    expect(r.largestSymbol, isNull);
    expect(r.investedFraction, 0);
    expect(r.largestPositionFraction, 0);
    expect(r.availableCashFraction, 1);
    expect(r.highConcentration, false);
    expect(r.lowLiquidity, false);
    expect(session.exportJson(), before);
  });

  test('executed market purchase uses only committed inventory and prices', () {
    final session = TxSession.fresh();
    final order = session.placePlayer(symbol: TxSession.symbols.first,
        side: TxSide.buy, kind: TxKind.market, quantity: 100);
    expect(order.filled, 100);
    final before = session.exportJson();
    final r = TxPortfolioRisk.compute(session);
    final player = session.engine.account(TxSession.playerId);
    expect(r.investedCents,
        player.sharesOf(TxSession.symbols.first) *
            session.lastPrice(TxSession.symbols.first));
    expect(r.equityCents, session.totalAssetsCents);
    expect(r.largestSymbol, TxSession.symbols.first);
    expect(r.largestPositionFraction, 1);
    expect(r.highConcentration, true);
    expect(r.investedFraction, greaterThan(0));
    expect(r.investedFraction, lessThanOrEqualTo(1));
    expect(session.exportJson(), before);
  });

  test('resting limit order reduces liquidity without inventing exposure', () {
    final session = TxSession.fresh();
    final before = TxPortfolioRisk.compute(session);
    final order = session.placePlayer(symbol: TxSession.symbols.first,
        side: TxSide.buy, kind: TxKind.limit,
        quantity: 50, limitPriceCents: 800);
    expect(order.status, TxStatus.open);
    final after = TxPortfolioRisk.compute(session);
    expect(after.investedCents, before.investedCents);
    expect(after.equityCents, before.equityCents);
    expect(after.reservedCashCents, 40000);
    expect(after.availableCashCents, before.availableCashCents - 40000);
    expect(after.availableCashFraction, lessThan(before.availableCashFraction));
  });

  test('reloading a saved snapshot preserves risk metrics', () {
    final original = TxSession.fresh();
    original.placePlayer(symbol: TxSession.symbols.first,
        side: TxSide.buy, kind: TxKind.market, quantity: 100);
    final copy = TxSession.importJson(original.exportJson());
    final a = TxPortfolioRisk.compute(original);
    final b = TxPortfolioRisk.compute(copy);
    expect(b.equityCents, a.equityCents);
    expect(b.availableCashCents, a.availableCashCents);
    expect(b.investedCents, a.investedCents);
    expect(b.largestSymbol, a.largestSymbol);
    expect(b.largestPositionFraction, a.largestPositionFraction);
  });

  test('fraction thresholds are bounded and non-mutating', () {
    const r = TxPortfolioRiskSnapshot(
      equityCents: 1000, cashCents: 90, availableCashCents: 90,
      reservedCashCents: 0, investedCents: 910,
      largestSymbol: 'SIM-A01', largestPositionCents: 800,
    );
    expect(r.investedFraction, closeTo(.91, .000001));
    expect(r.availableCashFraction, closeTo(.09, .000001));
    expect(r.largestPositionFraction, closeTo(800 / 910, .000001));
    expect(r.highConcentration, true);
    expect(r.lowLiquidity, true);
  });


  test('cash-only portfolio is unchanged by market shocks',(){
    final s=TxSession.fresh();
    final before=s.exportJson();
    for(final shock in [-2000,-1000,-500,0,500]) {
      final x=TxPortfolioScenarios.evaluate(s,shock);
      expect(x.changeCents,0);
    }
    expect(s.exportJson(),before);
  });
  test('holding portfolio downside reduces marked assets, not cash',(){
    final s=TxSession.fresh();
    s.placePlayer(symbol:TxSession.symbols[0],side:TxSide.buy,
      kind:TxKind.market,quantity:100);
    final oldCash=s.engine.account(TxSession.playerId).cashCents;
    final before=s.exportJson();
    final risk=TxPortfolioScenarios.evaluate(s,-1000);
    expect(risk.projectedAssetsCents,lessThan(risk.startAssetsCents));
    expect(risk.changeCents,isNegative);
    expect(s.engine.account(TxSession.playerId).cashCents,oldCash);
    expect(s.exportJson(),before);
  });
  test('invalid or catastrophic shocks fail closed',(){
    final s=TxSession.fresh();
    expect(()=>TxPortfolioScenarios.evaluate(s,-10000),throwsArgumentError);
    expect(()=>TxPortfolioScenarios.evaluate(s,100001),throwsArgumentError);
  });

}
