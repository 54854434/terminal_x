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

/// A small, read-only research exercise for the long closed-market interval.
/// The prompt is derived from the same verified session/venue snapshot shown
/// elsewhere on the page. It never places an order, awards a fill or writes a
/// score into the account/SQLite snapshot.
class TxMarketResearchPrompt {
  const TxMarketResearchPrompt({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
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

  /// Produce one deterministic, context-aware question. A changed committed
  /// minute changes the prompt id, so a new market state cannot inherit an old
  /// answer. The challenge is deliberately transient UI state, not gameplay
  /// money or a second persistence model.
  static TxMarketResearchPrompt researchPrompt(
      TxSession session, String symbol) {
    final index = TxSession.symbols.indexOf(symbol);
    if (index < 0) throw ArgumentError.value(symbol, 'symbol');
    final status = session.marketSessionStatus;
    final seed = ((session.step ~/ TxSession.marketRegimeMinutes) + index) % 3;
    final id = 'research-${session.step}-$symbol-${status.state.name}-$seed';
    TxMarketResearchPrompt prompt({
      required String question,
      required List<String> options,
      required int correctIndex,
      required String explanation,
    }) => TxMarketResearchPrompt(
          id: id,
          question: question,
          options: List<String>.unmodifiable(options),
          correctIndex: correctIndex,
          explanation: explanation,
        );

    if (!status.isOpen) {
      switch (seed) {
        case 0:
          return prompt(
            question: '休市期间，哪项描述符合当前真实市场状态？',
            options: <String>[
              '会继续生成真实成交',
              '不生成成交，也不推进临时 K 线波动',
              '把指示价直接写入收盘价',
            ],
            correctIndex: 1,
            explanation: '休市只暂停真实撮合；已提交历史、账户和挂单状态仍可复盘。',
          );
        case 1:
          return prompt(
            question: '想让下一笔交易进入真实账本，正确做法是什么？',
            options: <String>[
              '等下一次开市后按真实盘口下单',
              '把半透明预览 K 线转成成交',
              '手动修改参考价制造成交',
            ],
            correctIndex: 0,
            explanation: '只有通过开市门禁并完成订单簿撮合的订单，才会改变现金、持仓和成交记录。',
          );
        default:
          return prompt(
            question: '盘后研究时，哪项资料最适合用来复盘？',
            options: <String>[
              '已提交的盘口和历史真实成交',
              '猜测下一根 K 线的涨跌',
              '把实时预览影线当作成交极值',
            ],
            correctIndex: 0,
            explanation: '盘口是当前可见挂单快照，成交量和 OHLC 只认真实撮合。',
          );
      }
    }

    final current = briefing(session, symbol);
    if (seed == 0) {
      final pressure = current.pressure;
      final options = <String>[
        '买盘偏厚',
        '卖盘偏厚',
        pressure == '暂无双边流动性' ? '暂无双边流动性' : '买卖相对均衡',
      ];
      final correctIndex = switch (pressure) {
        '买盘偏厚' => 0,
        '卖盘偏厚' => 1,
        _ => 2,
      };
      return prompt(
        question: '读盘挑战：当前可见盘口压力应如何描述？',
        options: options,
        correctIndex: correctIndex,
        explanation: '盘口压力只是当前可见挂单的快照，不是对未来涨跌的保证。',
      );
    }
    if (seed == 1) {
      final spread = current.spreadCents == null
          ? '暂无双边价差'
          : '价差 ${current.spreadCents} 分';
      return prompt(
        question: '下单前最应该先确认什么？当前读数：$spread。',
        options: const <String>[
          '可见深度、VWAP 和最差成交价',
          '只看半透明实时预览线',
          '忽略资金与可卖数量',
        ],
        correctIndex: 0,
        explanation: '大额订单可能消耗多档流动性；执行预览不等于已成交，但能帮助控制冲击。',
      );
    }
    return prompt(
      question: '实时预览与真实 K 线的边界是什么？',
      options: const <String>[
        '预览只用于观察，不进入成交、OHLCV 或存档',
        '预览会自动增加成交量',
        '预览可以绕过交易时段门禁',
      ],
      correctIndex: 0,
      explanation: '真实 K 线、成交量、账户和 SQLite 只接受经过撮合并确认的状态。',
    );
  }
}
