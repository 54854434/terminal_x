import 'dart:math' as math;

import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import 'tx_market_phase_timeline.dart';
import 'tx_order_book_insight.dart';

/// A read-only game layer built from the real session state. It does not
/// place orders, award synthetic fills or persist a second account state.
class TxMarketObjective {
  const TxMarketObjective({
    required this.id,
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.unit,
  });

  final String id;
  final String title;
  final String description;
  final int progress;
  final int target;
  final String unit;

  bool get complete => progress >= target;
  double get fraction => target <= 0
      ? 0
      : (progress / target).clamp(0.0, 1.0).toDouble();
}

class TxMarketBriefing {
  const TxMarketBriefing({
    required this.regime,
    required this.liquidity,
    required this.pressure,
    required this.spreadCents,
    required this.bidShareFraction,
    required this.nextPhaseInMinutes,
  });

  final String regime;
  final String liquidity;
  final String pressure;
  final int? spreadCents;
  final double? bidShareFraction;
  final int nextPhaseInMinutes;
}

class TxMarketObjectives {
  const TxMarketObjectives._();

  static List<TxMarketObjective> evaluate(TxSession session, String symbol) {
    final index = TxSession.symbols.indexOf(symbol);
    if (index < 0) throw ArgumentError.value(symbol, 'symbol');
    final account = session.engine.account(TxSession.playerId);
    final bids = session.engine.depth(symbol, TxSide.buy);
    final asks = session.engine.depth(symbol, TxSide.sell);
    final bookLevels = math.min(10, bids.length + asks.length);
    final totalAssets = math.max(1, session.totalAssetsCents);
    final cashBuffer = (account.availableCashCents * 100 ~/ totalAssets)
        .clamp(0, 30).toInt();

    var limitShares = 0;
    for (final fill in session.engine.fills) {
      final buy = session.engine.order(fill.buyOrderId);
      final sell = session.engine.order(fill.sellOrderId);
      final playerOrder = buy.ownerId == TxSession.playerId ? buy :
          sell.ownerId == TxSession.playerId ? sell : null;
      if (playerOrder != null && playerOrder.symbol == symbol &&
          playerOrder.kind == TxKind.limit) {
        limitShares += fill.quantity;
      }
    }

    return <TxMarketObjective>[
      TxMarketObjective(
        id: 'limit-execution',
        title: '限价博弈',
        description: '用限价单完成真实撮合，观察价格优先与时间优先。',
        progress: math.min(3, limitShares),
        target: 3,
        unit: '股',
      ),
      TxMarketObjective(
        id: 'book-reading',
        title: '读懂盘口',
        description: '保持双边可见深度，先看流动性再决定是否吃单。',
        progress: bookLevels,
        target: 10,
        unit: '档',
      ),
      TxMarketObjective(
        id: 'cash-buffer',
        title: '现金缓冲',
        description: '保持至少 30% 可用资产，给滑点和波动留下余量。',
        progress: cashBuffer,
        target: 30,
        unit: '%',
      ),
    ];
  }

  static TxMarketBriefing briefing(TxSession session, String symbol) {
    final index = TxSession.symbols.indexOf(symbol);
    if (index < 0) throw ArgumentError.value(symbol, 'symbol');
    final bids = session.engine.depth(symbol, TxSide.buy);
    final asks = session.engine.depth(symbol, TxSide.sell);
    final insight = TxOrderBookInsight.fromLevels(bids: bids, asks: asks);
    final fraction = insight.bidShareFraction;
    final pressure = fraction == null
        ? '暂无双边流动性'
        : fraction > .58
            ? '买盘偏厚'
            : fraction < .42
                ? '卖盘偏厚'
                : '买卖相对均衡';
    final liquidity = insight.spreadBasisPoints == null
        ? '单边或空盘口'
        : insight.spreadBasisPoints! <= 20
            ? '价差紧'
            : insight.spreadBasisPoints! <= 80
                ? '价差中等'
                : '价差偏宽';
    final minute = session.step < 1 ? 1 : session.step;
    final phaseStart = ((minute - 1) ~/ TxSession.marketRegimeMinutes) *
        TxSession.marketRegimeMinutes + 1;
    final phaseEnd = phaseStart + TxSession.marketRegimeMinutes;
    return TxMarketBriefing(
      regime: TxMarketPhaseTimeline.regimeLabel(
          TxSession.marketRegime(minute, index)),
      liquidity: liquidity,
      pressure: pressure,
      spreadCents: insight.spreadCents,
      bidShareFraction: fraction,
      nextPhaseInMinutes: math.max(0, phaseEnd - session.step),
    );
  }
}
