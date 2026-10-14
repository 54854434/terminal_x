/// Instrument metadata shared by the market selector, preview UI and the
/// independent per-market Dart/Rust/SQLite trading cores.
///
/// Symbols are intentionally synthetic. They describe the game universe and
/// never claim to be live external prices or real exchange contracts.
class TxMarketInstrument {
  const TxMarketInstrument({
    required this.symbol,
    required this.name,
    required this.kind,
    required this.quoteCurrency,
    required this.orderUnit,
    required this.lotSize,
    required this.tickSize,
    required this.contractMultiplier,
    required this.contractMultiplierUnits,
    required this.usesMargin,
    required this.tPlusOne,
    required this.supportsShort,
    required this.coreConnected,
  });

  final String symbol;
  final String name;
  final String kind;
  final String quoteCurrency;
  final String orderUnit;
  final int lotSize;
  final String tickSize;
  final String contractMultiplier;
  /// Numeric multiplier used by the independent risk core. The display
  /// string above remains the user-facing contract description.
  final int contractMultiplierUnits;
  final bool usesMargin;
  final bool tPlusOne;
  final bool supportsShort;
  final bool coreConnected;

  String get lotLabel => lotSize == 1 ? '1 $orderUnit' : '$lotSize $orderUnit';

  String get connectionLabel => coreConnected ? '已接入 Rust 核心' : '已接入独立核心';
}
