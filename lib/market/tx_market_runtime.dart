import 'dart:convert';

import '../engine/tx_engine.dart';
import 'tx_market_profiles.dart';
import 'tx_market_risk_core.dart';
import 'tx_market_venue.dart';

/// Result of moving one independent market runtime clock forward.
///
/// A clock transition never invents a quote or a fill. Crossing a game-day
/// boundary deliberately invokes the venue's atomic settlement and exposes
/// its post-settlement risk snapshots to the caller.
class TxMarketClockAdvance {
  const TxMarketClockAdvance({
    required this.fromGameDay,
    required this.fromMinuteOfDay,
    required this.toGameDay,
    required this.toMinuteOfDay,
    required this.settlement,
    required this.riskSnapshots,
  });

  final int fromGameDay;
  final int fromMinuteOfDay;
  final int toGameDay;
  final int toMinuteOfDay;
  final TxMarketVenueSettlement? settlement;
  final Map<String, TxMarketRiskSnapshot> riskSnapshots;

  bool get crossedGameDay => settlement != null;
}

/// Runtime boundary for one independent market mode.
///
/// The connected A-share session continues to use [TxSession]. This class is
/// intentionally independent so the future Flutter/Rust/SQLite adapter can
/// own a complete multi-account market without relabeling the A-share ledger.
/// It is also deliberately feed-agnostic: a caller supplies validated marks,
/// and the venue supplies all actual executions.
class TxMarketRuntime {
  static const snapshotSchema = 1;

  TxMarketRuntime({
    required this.venue,
    required this.gameDay,
    required this.minuteOfDay,
    this.markRevision = 0,
  }) {
    _validateClock(gameDay, minuteOfDay);
    if (markRevision < 0) {
      throw ArgumentError.value(markRevision, 'markRevision');
    }
    for (final account in venue.accounts.values) {
      if (account.gameDay != gameDay) {
        throw StateError('Runtime and venue game days are inconsistent');
      }
    }
  }

  final TxMarketVenue venue;
  int gameDay;
  int minuteOfDay;
  int markRevision;

  TxMarketMode get mode => venue.profile.mode;

  Map<String, TxMarketRiskSnapshot> get riskSnapshots =>
      venue.riskSnapshots;

  /// Broadcast one externally supplied synthetic mark through the venue.
  /// The revision is advanced only after every account accepts the mark.
  Map<String, TxMarketRiskSnapshot> markToMarket({
    required String symbol,
    required int priceCents,
  }) {
    final snapshots = venue.markToMarket(
      symbol: symbol,
      priceCents: priceCents,
    );
    markRevision++;
    return snapshots;
  }

  /// Place an order at the runtime's current game time.
  TxMarketVenueOrder place({
    required String id,
    required String ownerId,
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    required int? limitPriceCents,
    required TxTimeInForce timeInForce,
    bool reduceOnly = false,
  }) => venue.place(
        id: id,
        ownerId: ownerId,
        symbol: symbol,
        side: side,
        kind: kind,
        quantity: quantity,
        limitPriceCents: limitPriceCents,
        timeInForce: timeInForce,
        gameDay: gameDay,
        minuteOfDay: minuteOfDay,
        reduceOnly: reduceOnly,
      );

  TxMarketVenueOrder cancel(String id, {required String ownerId}) =>
      venue.cancel(id, ownerId: ownerId);

  /// Move time monotonically and settle exactly once when the day changes.
  ///
  /// Same-day movement only changes the runtime clock. A multi-day jump is
  /// represented by one venue settlement carrying the exact day count; the
  /// caller can persist the returned batch together with this runtime.
  TxMarketClockAdvance advanceClock({
    required int nextGameDay,
    required int nextMinuteOfDay,
  }) {
    _validateClock(nextGameDay, nextMinuteOfDay);
    if (nextGameDay < gameDay ||
        (nextGameDay == gameDay && nextMinuteOfDay < minuteOfDay)) {
      throw ArgumentError('Market runtime clock cannot move backwards');
    }
    final fromDay = gameDay;
    final fromMinute = minuteOfDay;
    TxMarketVenueSettlement? settlement;
    if (nextGameDay > gameDay) {
      settlement = venue.settleDay(nextGameDay: nextGameDay);
    }
    gameDay = nextGameDay;
    minuteOfDay = nextMinuteOfDay;
    return TxMarketClockAdvance(
      fromGameDay: fromDay,
      fromMinuteOfDay: fromMinute,
      toGameDay: gameDay,
      toMinuteOfDay: minuteOfDay,
      settlement: settlement,
      riskSnapshots: settlement?.riskSnapshots ?? riskSnapshots,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': snapshotSchema,
        'mode': mode.name,
        'gameDay': gameDay,
        'minuteOfDay': minuteOfDay,
        'markRevision': markRevision,
        'venue': venue.toJson(),
      };

  String exportJson() => jsonEncode(toJson());

  static TxMarketRuntime fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid market runtime JSON');
    }
    return fromJsonMap(Map<String, dynamic>.from(decoded));
  }

  static TxMarketRuntime fromJsonMap(Map<String, dynamic> data) {
    if (data['schema'] != snapshotSchema || data['mode'] is! String ||
        data['gameDay'] is! int || data['minuteOfDay'] is! int ||
        data['markRevision'] is! int || data['venue'] is! Map) {
      throw const FormatException('Invalid market runtime snapshot');
    }
    try {
      final mode = TxMarketMode.values.firstWhere(
        (value) => value.name == data['mode'],
        orElse: () => throw const FormatException('Unknown runtime mode'),
      );
      final venue = TxMarketVenue.fromJsonMap(
          Map<String, dynamic>.from(data['venue'] as Map));
      if (venue.profile.mode != mode) {
        throw const FormatException('Runtime and venue modes differ');
      }
      return TxMarketRuntime(
        venue: venue,
        gameDay: data['gameDay'] as int,
        minuteOfDay: data['minuteOfDay'] as int,
        markRevision: data['markRevision'] as int,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid market runtime snapshot: $error');
    }
  }

  static void _validateClock(int day, int minute) {
    if (day < 1 || minute < 0 || minute >= 1440) {
      throw ArgumentError('Invalid market runtime clock');
    }
  }
}
