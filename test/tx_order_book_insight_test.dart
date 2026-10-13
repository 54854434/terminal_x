import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_order_book_insight.dart';

void main() {
  test('empty market is not misidentified as balanced liquidity', () {
    final r = TxOrderBookInsight.fromLevels(bids: [], asks: []);
    expect(r.hasBothSides, false);
    expect(r.spreadCents, isNull);
    expect(r.spreadBasisPoints, isNull);
    expect(r.bidShareFraction, isNull);
    expect(r.bidShares + r.askShares, 0);
  });

  test('five-depth spread, bps, visible volumes and order counts', () {
    final r = TxOrderBookInsight.fromLevels(
      bids: [const TxBookLevel(995, 30, 2), const TxBookLevel(990, 70, 1)],
      asks: [const TxBookLevel(1005, 50, 1), const TxBookLevel(1015, 50, 3)],
    );
    expect(r.bestBidCents, 995);
    expect(r.bestAskCents, 1005);
    expect(r.spreadCents, 10);
    expect(r.spreadBasisPoints, closeTo(100.0, .0000001));
    expect(r.bidShares, 100);
    expect(r.askShares, 100);
    expect(r.bidOrders, 3);
    expect(r.askOrders, 4);
    expect(r.bidShareFraction, closeTo(.5, .0000001));
  });

  test('one-sided depth does not invent an opposite best price', () {
    final r = TxOrderBookInsight.fromLevels(
        bids: [const TxBookLevel(900, 20, 1)], asks: []);
    expect(r.bestAskCents, isNull);
    expect(r.spreadCents, isNull);
    expect(r.bidShareFraction, 1.0);
  });

  test('sell-heavy depth is a ratio, not an automatic trade signal', () {
    final r = TxOrderBookInsight.fromLevels(
      bids: [const TxBookLevel(1000, 10, 1)],
      asks: [const TxBookLevel(1001, 90, 2)],
    );
    expect(r.bidShareFraction, closeTo(.1, .0000001));
  });

  test('invalid quantities or order counts fail closed', () {
    expect(() => TxOrderBookInsight.fromLevels(
      bids: [const TxBookLevel(1000, 0, 1)], asks: []), throwsStateError);
    expect(() => TxOrderBookInsight.fromLevels(
      bids: [], asks: [const TxBookLevel(1001, 1, 0)]), throwsStateError);
  });

  test('unsorted and duplicate price levels fail closed', () {
    expect(() => TxOrderBookInsight.fromLevels(bids: [
      const TxBookLevel(990, 1, 1), const TxBookLevel(1000, 1, 1),
    ], asks: []), throwsStateError);
    expect(() => TxOrderBookInsight.fromLevels(bids: [], asks: [
      const TxBookLevel(1000, 1, 1), const TxBookLevel(1000, 1, 1),
    ]), throwsStateError);
  });

  test('crossed resting book fails instead of reporting negative spread', () {
    expect(() => TxOrderBookInsight.fromLevels(
      bids: [const TxBookLevel(1005, 10, 1)],
      asks: [const TxBookLevel(1000, 10, 1)],
    ), throwsStateError);
  });

  test('actual session book snapshot is read-only and reproducible', () {
    final session = TxSession.fresh();
    final before = session.exportJson();
    final symbol = TxSession.symbols.first;
    final r = TxOrderBookInsight.fromLevels(
      bids: session.engine.depth(symbol, TxSide.buy),
      asks: session.engine.depth(symbol, TxSide.sell),
    );
    expect(r.bidShares, greaterThanOrEqualTo(0));
    expect(r.askShares, greaterThanOrEqualTo(0));
    expect(r.spreadCents, isNotNull);
    expect(r.spreadCents!, greaterThan(0));
    expect(session.exportJson(), before);
  });

  test('visible depth metrics stay grounded in the actual BBO', () {
    final r = TxOrderBookInsight.fromLevels(
      bids: [const TxBookLevel(1099, 20, 2)],
      asks: [const TxBookLevel(1101, 10, 1)],
    );
    expect(r.bestBidCents, 1099);
    expect(r.bestAskCents, 1101);
    expect(r.spreadCents, 2);
    expect(r.bidShareFraction, closeTo(2 / 3, .0000001));
  });
}
