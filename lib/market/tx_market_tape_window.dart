/// Bounded presentation window over the immutable chronological fill list.
/// This only limits UI rows; it NEVER deletes or edits real fills or ledgers.
class TxMarketTapeWindow {
  const TxMarketTapeWindow._();

  static const int pageSize = 24;
  static const int maximum = 120;

  static int visibleCount(int total, int requested) {
    if (total < 0 || requested < 1) {
      throw ArgumentError('Invalid market tape window');
    }
    final limit = requested > maximum ? maximum : requested;
    return total < limit ? total : limit;
  }

  static int newestFirstFillIndex(int total, int visualIndex) {
    if (total < 0 || visualIndex < 0 || visualIndex >= total) {
      throw RangeError.index(visualIndex, List<Object?>.filled(0, null));
    }
    return total - 1 - visualIndex;
  }

  static int expand(int currentlyRequested) {
    if (currentlyRequested < 1) throw ArgumentError.value(currentlyRequested);
    final next = currentlyRequested + pageSize;
    return next < maximum ? next : maximum;
  }
}
