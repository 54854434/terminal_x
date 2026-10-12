import 'package:flutter_test/flutter_test.dart';
import '../lib/market/tx_candle_history.dart';
import '../lib/market/tx_indicators.dart';
import '../lib/market/tx_quote_preview.dart';

void main() {
  test('MA 5/10/20 uses committed closes and gaps where insufficient', () {
    final candles = List.generate(25, (i) => TxCandle(
      step:i,openCents:1000+i,highCents:1002+i,
      lowCents:998+i,closeCents:1000+i,volumeShares:i));
    final ma5 = TxIndicators.sma(candles, 5);
    expect(ma5[3], isNull);
    expect(ma5[4], 1002.0);
    expect(ma5.last, 1022.0);
    expect(TxIndicators.sma(candles, 10).last, 1019.5);
    expect(TxIndicators.sma(candles, 20).last, 1014.5);
    expect(() => TxIndicators.sma(candles, 0), throwsArgumentError);
  });

  test('indicative intra-minute quote is deterministic and has no fills', () {
    expect(TxQuotePreview.cents(1000, 2, 0, 0), 1000);
    for (var second = 1; second < 60; second++) {
      final price = TxQuotePreview.cents(1000, 2, second, 0);
      expect(price, greaterThanOrEqualTo(1));
      expect(price, TxQuotePreview.cents(1000, 2, second, 0));
    }
  });
}
