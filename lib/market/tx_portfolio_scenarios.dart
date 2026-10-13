/// Offline what-if valuation; never mutates holdings, orders or SQLite.
import '../engine/tx_session.dart';

class TxPortfolioScenario {
  const TxPortfolioScenario({required this.shockBasisPoints,
    required this.startAssetsCents,required this.projectedAssetsCents,
    required this.changeCents});
  final int shockBasisPoints;
  final int startAssetsCents;
  final int projectedAssetsCents;
  final int changeCents;
  double get changePercent => startAssetsCents==0 ? 0 :
    changeCents * 100 / startAssetsCents;
}

class TxPortfolioScenarios {
  const TxPortfolioScenarios._();
  /// Apply a hypothetical common shock to all committed reference marks.
  /// Whole-cent rounding is explicit and zero/negative prices are forbidden.
  static TxPortfolioScenario evaluate(TxSession session,int shockBasisPoints) {
    if(shockBasisPoints<=-10000 || shockBasisPoints>100000) {
      throw ArgumentError.value(shockBasisPoints,'shockBasisPoints');
    }
    final account=session.engine.account(TxSession.playerId);
    var hypothetical=account.cashCents;
    for(final symbol in TxSession.symbols) {
      final price=session.lastPrice(symbol);
      final stressed=((price*(10000+shockBasisPoints)+5000)~/10000);
      hypothetical+=account.sharesOf(symbol)*(stressed<1?1:stressed);
    }
    final current=session.totalAssetsCents;
    return TxPortfolioScenario(shockBasisPoints:shockBasisPoints,
      startAssetsCents:current,projectedAssetsCents:hypothetical,
      changeCents:hypothetical-current);
  }
}
