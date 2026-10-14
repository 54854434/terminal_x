import '../engine/tx_engine.dart';
import 'tx_market_profiles.dart';
import 'tx_market_venue.dart';

/// Explicit labels for independent-market accounts. The label is metadata
/// supplied by the game scenario; it never creates liquidity or changes risk.
enum TxMarketActorRole { marketMaker, whale, retail, fund, unknown }

extension TxMarketActorRoleX on TxMarketActorRole {
  String get label => switch (this) {
    TxMarketActorRole.marketMaker => '做市商',
    TxMarketActorRole.whale => '鲸鱼/大户',
    TxMarketActorRole.retail => '散户',
    TxMarketActorRole.fund => '基金/游资',
    TxMarketActorRole.unknown => '未标注账户',
  };
}

class TxMarketActorProfile {
  const TxMarketActorProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.behaviour,
  });

  final String id;
  final String name;
  final TxMarketActorRole role;
  final String behaviour;
}

/// Real account projection for one instrument in an independent venue.
class TxMarketVenueParticipant {
  const TxMarketVenueParticipant({
    required this.profile,
    required this.equityCents,
    required this.cashCents,
    required this.netQuantity,
    required this.bidQuantity,
    required this.askQuantity,
    required this.activeOrders,
    required this.liquidationRequired,
  });

  final TxMarketActorProfile profile;
  final int equityCents;
  final int cashCents;
  final int netQuantity;
  final int bidQuantity;
  final int askQuantity;
  final int activeOrders;
  final bool liquidationRequired;

  int get visibleQuantity => bidQuantity + askQuantity;
}

/// Cross-account market-structure projection. Every quantity is derived from
/// the venue's actual order map and risk cores; role labels are descriptive
/// only and are never used as a hidden NPC fill source.
class TxMarketVenueEcosystemSnapshot {
  const TxMarketVenueEcosystemSnapshot({
    required this.mode,
    required this.symbol,
    required this.bidLevels,
    required this.askLevels,
    required this.spreadCents,
    required this.bookNotionalCents,
    required this.participants,
    required this.stats,
  });

  final TxMarketMode mode;
  final String symbol;
  final List<TxBookLevel> bidLevels;
  final List<TxBookLevel> askLevels;
  final int? spreadCents;
  final int bookNotionalCents;
  final List<TxMarketVenueParticipant> participants;
  final TxMarketVenueStats stats;

  int get bidQuantity => bidLevels.fold(0, (sum, level) => sum + level.quantity);
  int get askQuantity => askLevels.fold(0, (sum, level) => sum + level.quantity);
  int get activeParticipantCount => participants
      .where((participant) => participant.activeOrders > 0 ||
          participant.netQuantity != 0)
      .length;

  static TxMarketVenueEcosystemSnapshot evaluate({
    required TxMarketVenue venue,
    required String symbol,
    Map<String, TxMarketActorProfile> actors = const {},
  }) {
    final instrument = venue.profile.instruments.firstWhere(
        (item) => item.symbol == symbol,
        orElse: () => throw ArgumentError.value(symbol, 'symbol'));
    final bids = venue.depth(symbol, TxSide.buy, levels: 10);
    final asks = venue.depth(symbol, TxSide.sell, levels: 10);
    final spread = bids.isEmpty || asks.isEmpty
        ? null : asks.first.priceCents - bids.first.priceCents;
    var bookNotional = 0;
    for (final level in [...bids, ...asks]) {
      bookNotional += level.priceCents * level.quantity *
          instrument.contractMultiplierUnits;
    }

    final participants = <TxMarketVenueParticipant>[];
    final activeByOwner = <String, List<TxMarketVenueOrder>>{};
    for (final order in venue.activeOrders) {
      if (order.symbol != symbol) continue;
      activeByOwner.putIfAbsent(order.ownerId, () => []).add(order);
    }
    for (final entry in venue.accounts.entries) {
      final account = entry.value;
      final risk = account.snapshot();
      final position = risk.positions[symbol];
      final orders = activeByOwner[entry.key] ?? const <TxMarketVenueOrder>[];
      var bid = 0;
      var ask = 0;
      for (final order in orders) {
        if (order.side == TxSide.buy) {
          bid += order.remaining;
        } else {
          ask += order.remaining;
        }
      }
      final actor = actors[entry.key] ?? TxMarketActorProfile(
          id: entry.key,
          name: entry.key,
          role: TxMarketActorRole.unknown,
          behaviour: '未标注策略账户');
      if (actor.id != entry.key) {
        throw StateError('Participant label does not match account id');
      }
      participants.add(TxMarketVenueParticipant(
        profile: actor,
        equityCents: risk.equityCents,
        cashCents: risk.cashCents,
        netQuantity: position?.netQuantity ?? 0,
        bidQuantity: bid,
        askQuantity: ask,
        activeOrders: orders.length,
        liquidationRequired: risk.liquidationRequired,
      ));
    }
    return TxMarketVenueEcosystemSnapshot(
      mode: venue.profile.mode,
      symbol: symbol,
      bidLevels: List.unmodifiable(bids),
      askLevels: List.unmodifiable(asks),
      spreadCents: spread,
      bookNotionalCents: bookNotional,
      participants: List.unmodifiable(participants),
      stats: venue.stats,
    );
  }
}
