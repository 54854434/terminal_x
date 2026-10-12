import 'tx_candle_history.dart';

/// Historical moving averages are derived from committed candle closes only.
/// A partial, indicative candle is never silently included in SMA history.
class TxIndicators {
  const TxIndicators._();

  static List<double?> sma(List<TxCandle> candles, int period) {
    if (period < 1) throw ArgumentError.value(period, 'period');
    final result = <double?>[];
    var sum = 0;
    for (var i = 0; i < candles.length; i++) {
      sum += candles[i].closeCents;
      if (i >= period) sum -= candles[i-period].closeCents;
      result.add(i + 1 >= period ? sum / period : null);
    }
    return result;
  }
}
