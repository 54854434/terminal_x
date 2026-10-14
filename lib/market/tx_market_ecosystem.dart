import 'dart:math' as math;

import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import 'tx_market_book_impact.dart';
import 'tx_market_phase_timeline.dart';
import 'tx_order_book_insight.dart';

/// A real-state view of the simulated market participants. It does not place
/// orders, grant rewards or create a second account ledger.
class TxMarketParticipant {
  const TxMarketParticipant({
    required this.id,
    required this.name,
    required this.role,
    required this.behaviour,
    required this.inventoryShares,
    required this.availableCashCents,
    required this.equityCents,
    required this.bidShares,
    required this.askShares,
    required this.bidOrders,
    required this.askOrders,
    required this.minuteBuyShares,
    required this.minuteSellShares,
  });

  final String id;
  final String name;
  final String role;
  final String behaviour;
  final int inventoryShares;
  final int availableCashCents;
  final int equityCents;
  final int bidShares;
  final int askShares;
  final int bidOrders;
  final int askOrders;
  final int minuteBuyShares;
  final int minuteSellShares;

  int get visibleShares => bidShares + askShares;
  int get minuteNetShares => minuteBuyShares - minuteSellShares;
  int get visibleOrders => bidOrders + askOrders;
}

class TxMarketEcosystemSnapshot {
  const TxMarketEcosystemSnapshot({
    required this.symbol,
    required this.regime,
    required this.spreadCents,
    required this.bidShares,
    required this.askShares,
    required this.bidOrders,
    required this.askOrders,
    required this.bookNotionalCents,
    required this.playerEquityCents,
    required this.playerAvailableCashCents,
    required this.playerBuyImpact,
    required this.playerSellImpact,
    required this.participants,
  });

  final String symbol;
  final String regime;
  final int? spreadCents;
  final int bidShares;
  final int askShares;
  final int bidOrders;
  final int askOrders;
  final int bookNotionalCents;
  final int playerEquityCents;
  final int playerAvailableCashCents;
  final TxMarketBookImpact playerBuyImpact;
  final TxMarketBookImpact playerSellImpact;
  final List<TxMarketParticipant> participants;

  int get visibleShares => bidShares + askShares;
  int get visibleOrders => bidOrders + askOrders;

  /// This is a sizing signal, not an automatic price-impact mechanic. A
  /// value above 1 means the player's equity is larger than the current
  /// five-level visible book notional.
  double get capitalToBookRatio => bookNotionalCents <= 0
      ? 0.0 : playerEquityCents / bookNotionalCents;

  bool get hasNpcMarket => participants.isNotEmpty;

  static TxMarketEcosystemSnapshot evaluate(
      TxSession session, String symbol) {
    final symbolIndex = TxSession.symbols.indexOf(symbol);
    if (symbolIndex < 0) throw ArgumentError.value(symbol, 'symbol');

    final bids = session.engine.depth(symbol, TxSide.buy, levels: 10);
    final asks = session.engine.depth(symbol, TxSide.sell, levels: 10);
    final insight = TxOrderBookInsight.fromLevels(bids: bids, asks: asks);
    final player = session.engine.account(TxSession.playerId);
    final buyQuantity = asks.isEmpty || player.availableCashCents <= 0
        ? 0
        : (player.availableCashCents ~/ asks.first.priceCents)
            .clamp(0, insight.askShares).toInt();
    final sellQuantity = player.availableSharesOf(symbol)
        .clamp(0, insight.bidShares).toInt();
    final buyImpact = TxMarketBookImpact.estimate(
        side: TxSide.buy, levels: asks, quantity: buyQuantity);
    final sellImpact = TxMarketBookImpact.estimate(
        side: TxSide.sell, levels: bids, quantity: sellQuantity);
    var bookNotional = 0;
    for (final level in [...bids, ...asks]) {
      bookNotional += level.priceCents * level.quantity;
    }

    final orderStats = <String, _MutableBookStats>{};
    for (final order in session.engine.activeOrders) {
      if (order.symbol != symbol || !_profiles.containsKey(order.ownerId)) {
        continue;
      }
      final stats = orderStats.putIfAbsent(order.ownerId, _MutableBookStats.new);
      if (order.side == TxSide.buy) {
        stats.bidShares += order.remaining;
        stats.bidOrders++;
      } else {
        stats.askShares += order.remaining;
        stats.askOrders++;
      }
    }

    final minuteBuy = <String, int>{};
    final minuteSell = <String, int>{};
    for (final fill in session.currentMinuteFills) {
      final buy = session.engine.order(fill.buyOrderId).ownerId;
      final sell = session.engine.order(fill.sellOrderId).ownerId;
      if (_profiles.containsKey(buy)) {
        minuteBuy[buy] = (minuteBuy[buy] ?? 0) + fill.quantity;
      }
      if (_profiles.containsKey(sell)) {
        minuteSell[sell] = (minuteSell[sell] ?? 0) + fill.quantity;
      }
    }

    final participants = <TxMarketParticipant>[];
    for (final entry in _profiles.entries) {
      if (!session.engine.accounts.containsKey(entry.key)) continue;
      final account = session.engine.account(entry.key);
      final stats = orderStats[entry.key] ?? _MutableBookStats();
      var equity = account.cashCents;
      for (final item in TxSession.symbols) {
        equity += account.sharesOf(item) * session.lastPrice(item);
      }
      participants.add(TxMarketParticipant(
        id: entry.key,
        name: entry.value.name,
        role: entry.value.role,
        behaviour: entry.value.behaviour,
        inventoryShares: account.sharesOf(symbol),
        availableCashCents: account.availableCashCents,
        equityCents: math.max(0, equity),
        bidShares: stats.bidShares,
        askShares: stats.askShares,
        bidOrders: stats.bidOrders,
        askOrders: stats.askOrders,
        minuteBuyShares: minuteBuy[entry.key] ?? 0,
        minuteSellShares: minuteSell[entry.key] ?? 0,
      ));
    }

    return TxMarketEcosystemSnapshot(
      symbol: symbol,
      regime: TxMarketPhaseTimeline.regimeLabel(
          TxSession.marketRegime(session.step < 1 ? 1 : session.step,
              symbolIndex)),
      spreadCents: insight.spreadCents,
      bidShares: insight.bidShares,
      askShares: insight.askShares,
      bidOrders: insight.bidOrders,
      askOrders: insight.askOrders,
      bookNotionalCents: bookNotional,
      playerEquityCents: session.totalAssetsCents,
      playerAvailableCashCents: player.availableCashCents,
      playerBuyImpact: buyImpact,
      playerSellImpact: sellImpact,
      participants: List<TxMarketParticipant>.unmodifiable(participants),
    );
  }

  static const _profiles = <String, _ParticipantProfile>{
    'NPC_LIQ': _ParticipantProfile(
        name: '流动性做市商', role: '做市商', behaviour: '双边报价 · 库存偏斜'),
    'NPC_TREND': _ParticipantProfile(
        name: '趋势游资', role: '游资', behaviour: '趋势跟随 · 保护性 IOC'),
    'NPC_VALUE': _ParticipantProfile(
        name: '价值资金', role: '中长线资金', behaviour: '逆向报价 · 控制滑点'),
    'NPC_FLOW': _ParticipantProfile(
        name: '分散流量', role: '散户流', behaviour: '小额分散 · 噪声方向'),
  };
}

class _ParticipantProfile {
  const _ParticipantProfile({
    required this.name,
    required this.role,
    required this.behaviour,
  });
  final String name;
  final String role;
  final String behaviour;
}

class _MutableBookStats {
  int bidShares = 0;
  int askShares = 0;
  int bidOrders = 0;
  int askOrders = 0;
}
