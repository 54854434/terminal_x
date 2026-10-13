/// Read-only portfolio concentration, liquidity and exposure diagnostics.
/// These values are computed ONLY from authoritative committed account state.
/// No orders, virtual executions, synthetic candles, or storage writes occur.
import '../engine/tx_session.dart';

class TxPortfolioRiskSnapshot {
  const TxPortfolioRiskSnapshot({
    required this.equityCents,
    required this.cashCents,
    required this.availableCashCents,
    required this.reservedCashCents,
    required this.investedCents,
    required this.largestSymbol,
    required this.largestPositionCents,
  });

  final int equityCents;
  final int cashCents;
  final int availableCashCents;
  final int reservedCashCents;
  final int investedCents;
  final String? largestSymbol;
  final int largestPositionCents;

  double get investedFraction =>
      equityCents <= 0 ? 0.0 : investedCents / equityCents;
  double get availableCashFraction =>
      equityCents <= 0 ? 0.0 : availableCashCents / equityCents;
  double get largestPositionFraction =>
      investedCents <= 0 ? 0.0 : largestPositionCents / investedCents;
  // These are optional informational thresholds for a fictional game.
  bool get highConcentration =>
      investedCents > 0 && largestPositionFraction >= .75;
  bool get lowLiquidity =>
      equityCents > 0 && availableCashFraction < .10;
}

class TxPortfolioRisk {
  const TxPortfolioRisk._();

  static TxPortfolioRiskSnapshot compute(TxSession session) {
    final account = session.engine.account(TxSession.playerId);
    var invested = 0;
    var largest = 0;
    String? largestSymbol;
    for (final symbol in TxSession.symbols) {
      final value = account.sharesOf(symbol) * session.lastPrice(symbol);
      invested += value;
      if (value > largest) {
        largest = value;
        largestSymbol = symbol;
      }
    }
    final equity = account.cashCents + invested;
    if (equity != session.totalAssetsCents || invested < 0 ||
        account.availableCashCents < 0 ||
        account.availableCashCents > account.cashCents ||
        account.reservedCashCents < 0) {
      throw StateError('Inconsistent verified portfolio state');
    }
    return TxPortfolioRiskSnapshot(
      equityCents: equity,
      cashCents: account.cashCents,
      availableCashCents: account.availableCashCents,
      reservedCashCents: account.reservedCashCents,
      investedCents: invested,
      largestSymbol: largestSymbol,
      largestPositionCents: largest,
    );
  }
}
