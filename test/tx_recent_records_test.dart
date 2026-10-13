import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/market/tx_market_tape_window.dart';
import '../lib/market/tx_live_portfolio_valuation.dart';
import '../lib/market/tx_position_analytics.dart';

void main() {
  test('bounded recent player fills retain newest-first real execution order', () {
    final session = TxSession.fresh();
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 2);
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 3);
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.sell,
        kind: TxKind.market, quantity: 1);
    final all = session.playerFills;
    expect(all.length, greaterThanOrEqualTo(2));
    expect(session.recentPlayerFills(limit: 2).map((f) => f.id).toList(),
        all.take(2).map((f) => f.id).toList());
    expect(session.recentPlayerFills(limit: 100).map((f) => f.id).toList(),
        all.map((f) => f.id).toList());
    final restored = TxSession.importJson(session.exportJson());
    expect(restored.recentPlayerFills(limit: 2).map((f) => f.id).toList(),
        all.take(2).map((f) => f.id).toList());
    restored.engine.checkInvariants();
  });

  test('empty and invalid bounded player fill queries fail safely', () {
    final session = TxSession.fresh();
    expect(session.recentPlayerFills(limit: 1), isEmpty);
    expect(session.playerFills, isEmpty);
    expect(() => session.recentPlayerFills(limit: 0), throwsArgumentError);
    expect(() => session.recentPlayerFills(limit: -5), throwsArgumentError);
  });

  test('read-only bounded history never modifies saved economic state', () {
    final session = TxSession.fresh();
    session.placePlayer(symbol: 'SIM-A01', side: TxSide.buy,
        kind: TxKind.market, quantity: 4);
    final original = session.exportJson();
    for (var i = 0; i < 10; i++) {
      session.recentPlayerFills(limit: 1);
    }
    expect(session.exportJson(), original);
  });

  test('R34 tape limits, paginates and keeps newest real fills intact', () {
    expect(TxMarketTapeWindow.visibleCount(100000, 24), 24);
    expect(TxMarketTapeWindow.visibleCount(8, 24), 8);
    expect(TxMarketTapeWindow.visibleCount(100000, 200), 120);
    expect(TxMarketTapeWindow.visibleCount(150, 200), 120);
    expect(TxMarketTapeWindow.expand(24), 48);
    expect(TxMarketTapeWindow.expand(116), 120);
    expect(TxMarketTapeWindow.newestFirstFillIndex(12345, 0), 12344);
    expect(TxMarketTapeWindow.newestFirstFillIndex(12345, 23), 12321);
    expect(() => TxMarketTapeWindow.newestFirstFillIndex(2, 2), throwsRangeError);
    expect(() => TxMarketTapeWindow.visibleCount(-1, 24), throwsArgumentError);
  });

  test('R34 asset marks move with frame price without settling cash or shares', () {
    final s = TxSession.fresh();
    s.placePlayer(symbol: TxSession.symbols[0], side: TxSide.buy,
        kind: TxKind.market, quantity: 100);
    final account = s.engine.account(TxSession.playerId);
    final cash = account.cashCents;
    final shares = account.sharesOf(TxSession.symbols[0]);
    final frozen = account.reservedCashCents;
    final fills = s.engine.fillCount;
    final positions = TxPositionAnalytics.compute(s);
    final atStart = TxLivePortfolioValuation.evaluate(s, positions, 0);
    expect(atStart.totalAssetsCents, s.totalAssetsCents);
    for (final second in <double>[5, 17, 31, 49, 59.5]) {
      final mark = TxLivePortfolioValuation.evaluate(s, positions, second);
      expect(mark.totalAssetsCents, cash +
          TxSession.symbols.fold<int>(0, (sum, symbol) =>
              sum + account.sharesOf(symbol) * mark.pricesCents[symbol]!));
      expect(account.cashCents, cash);
      expect(account.sharesOf(TxSession.symbols[0]), shares);
      expect(account.reservedCashCents, frozen);
      expect(s.engine.fillCount, fills);
    }
    expect(() => TxLivePortfolioValuation.evaluate(s, positions, 60),
        throwsArgumentError);
  });
}
