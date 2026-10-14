import 'package:flutter/material.dart';

import '../market/tx_market_venue_ecosystem.dart';
import '../market/tx_market_venue.dart';
import 'tx_terminal_theme.dart';

/// Visible cross-account structure for an independent venue. It deliberately
/// has no quest/story copy: the feedback is book, risk and participant flow.
class TxMarketVenueEcosystemCard extends StatelessWidget {
  const TxMarketVenueEcosystemCard({
    super.key,
    required this.venue,
    required this.symbol,
    this.actors = const {},
  });

  final TxMarketVenue venue;
  final String symbol;
  final Map<String, TxMarketActorProfile> actors;

  String _money(int cents) => '${venue.profile.quoteCurrency} '
      '${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final snapshot = TxMarketVenueEcosystemSnapshot.evaluate(
        venue: venue, symbol: symbol, actors: actors);
    final spread = snapshot.spreadCents == null
        ? '—' : _money(snapshot.spreadCents!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.groups_2_outlined,
                size: 19, color: TxTerminalColors.primary),
            const SizedBox(width: 7),
            Expanded(child: Text('${venue.profile.label}博弈结构 · $symbol',
                style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${snapshot.activeParticipantCount} 个活跃账户',
                style: const TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
          ]),
          const SizedBox(height: 7),
          Wrap(spacing: 6, runSpacing: 5, children: [
            _chip('买盘 ${snapshot.bidQuantity}', TxTerminalColors.buy),
            _chip('卖盘 ${snapshot.askQuantity}', TxTerminalColors.sell),
            _chip('价差 $spread', TxTerminalColors.cyan),
            _chip('盘口 ${_money(snapshot.bookNotionalCents)}', Colors.white70),
          ]),
          const SizedBox(height: 8),
          Text('盘口读取缓存 ${(snapshot.stats.depthCacheHitRate * 100).toStringAsFixed(0)}% 命中 · '
              '修订 ${snapshot.stats.bookRevision} · 成交 ${snapshot.stats.fillCount} 笔',
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
          const SizedBox(height: 8),
          for (final participant in snapshot.participants)
            _participantRow(participant),
          if (snapshot.participants.isEmpty)
            const Text('暂无账户快照', style: TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
        ]),
      ),
    );
  }

  Widget _participantRow(TxMarketVenueParticipant participant) {
    final roleColor = switch (participant.profile.role) {
      TxMarketActorRole.marketMaker => TxTerminalColors.cyan,
      TxMarketActorRole.whale => TxTerminalColors.primary,
      TxMarketActorRole.fund => const Color(0xFFE38FE8),
      TxMarketActorRole.retail => TxTerminalColors.buy,
      TxMarketActorRole.unknown => TxTerminalColors.secondaryText,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 31,
            decoration: BoxDecoration(color: roleColor,
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 7),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(participant.profile.name,
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(participant.profile.role.label,
                style: TextStyle(fontSize: 10, color: roleColor)),
            if (participant.liquidationRequired) ...[
              const SizedBox(width: 6),
              const Text('需强平', style: TextStyle(fontSize: 10,
                  color: TxMarketColors.liquidation)),
            ],
          ]),
          Text('${participant.profile.behaviour} · '
              '挂买 ${participant.bidQuantity} / 挂卖 ${participant.askQuantity} · '
              '净仓 ${participant.netQuantity} · 权益 ${_money(participant.equityCents)}',
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
        ])),
        Text('${participant.activeOrders}笔', style: const TextStyle(fontSize: 10,
            color: TxTerminalColors.secondaryText)),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(100)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );
}

// Kept local to this display-only widget so the domain model does not depend
// on Flutter colors.
class TxMarketColors {
  static const liquidation = Color(0xFFFF6B7A);
}
