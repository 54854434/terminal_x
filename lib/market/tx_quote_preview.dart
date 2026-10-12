import 'dart:math' as math;

/// Deterministic indicative intra-minute reference-price preview.
/// No actual execution, zero invented fill volume, no storage write.
/// A real match continues to use the committed bid/ask book.
class TxQuotePreview {
  const TxQuotePreview._();
  static int cents(int committedPriceCents, int minute, int second,
      int symbolIndex) {
    if (committedPriceCents < 1 || minute < 0 ||
        second < 0 || second >= 60 || symbolIndex < 0) {
      throw ArgumentError('Invalid indicative quote input');
    }
    if (second == 0) return committedPriceCents;
    final amplitude = math.max(2, (committedPriceCents / 190).round());
    final phase = minute * 0.83 + symbolIndex * 1.93;
    final move = (amplitude * (
      .68 * (math.sin(second * .28 + phase) - math.sin(phase)) +
      .32 * (math.sin(second * .79 + phase * 2) - math.sin(phase * 2))
    )).round();
    return math.max(1, committedPriceCents + move);
  }
}
