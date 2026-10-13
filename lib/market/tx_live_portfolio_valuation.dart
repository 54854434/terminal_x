/// Read-only intraminute marks. Settlement, ownership, frozen funds and
/// recorded P/L remain sourced only from verified SQLite trade executions.
import '../engine/tx_session.dart';
import 'tx_frame_preview.dart';
import 'tx_position_analytics.dart';

class TxLivePortfolioMark {
  const TxLivePortfolioMark(this.pricesCents, this.marketValuesCents,
      this.totalAssetsCents, this.unrealizedPnlCents);
  final Map<String, int> pricesCents;
  final Map<String, int> marketValuesCents;
  final int totalAssetsCents;
  final int? unrealizedPnlCents;
}

class TxLivePortfolioValuation {
  const TxLivePortfolioValuation._();

  static TxLivePortfolioMark evaluate(TxSession session,
      Map<String, TxPosition> positions, double seconds) {
    if (!seconds.isFinite || seconds < 0 || seconds >= 60) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    final account = session.engine.account(TxSession.playerId);
    final prices = <String, int>{};
    final values = <String, int>{};
    var total = account.cashCents;
    var unrealized = 0;
    var allCostsKnown = true;
    for (var i = 0; i < TxSession.symbols.length; i++) {
      final symbol = TxSession.symbols[i];
      final price = TxFrameQuote.cents(
          session.lastPrice(symbol), session.step, seconds, i).round();
      final value = account.sharesOf(symbol) * price;
      prices[symbol] = price;
      values[symbol] = value;
      total += value;
      final position = positions[symbol];
      if (position == null || !position.costKnown ||
          position.quantity != account.sharesOf(symbol)) {
        allCostsKnown = false;
      } else {
        unrealized += value - position.costBasisCents;
      }
    }
    return TxLivePortfolioMark(prices, values, total,
        allCostsKnown ? unrealized : null);
  }
}
