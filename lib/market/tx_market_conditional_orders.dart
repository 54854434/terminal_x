import '../engine/tx_engine.dart';

/// A durable protection instruction owned by one independent-market account.
///
/// This is deliberately not a venue order. It remains outside the visible
/// book until its saved mark satisfies [shouldTrigger], at which point the
/// market worker submits a normal reduce-only market order. That distinction
/// keeps stop/limit intent auditable without pretending that a trigger is a
/// fill or that a stop order has infinite liquidity.
enum TxMarketConditionalOrderKind { stopLoss, takeProfit }

extension TxMarketConditionalOrderKindLabel
    on TxMarketConditionalOrderKind {
  String get label => switch (this) {
        TxMarketConditionalOrderKind.stopLoss => '止损',
        TxMarketConditionalOrderKind.takeProfit => '止盈',
      };

  String get nameForJson => switch (this) {
        TxMarketConditionalOrderKind.stopLoss => 'stopLoss',
        TxMarketConditionalOrderKind.takeProfit => 'takeProfit',
      };

  static TxMarketConditionalOrderKind fromJsonValue(Object? value) =>
      switch (value) {
        'stopLoss' => TxMarketConditionalOrderKind.stopLoss,
        'takeProfit' => TxMarketConditionalOrderKind.takeProfit,
        _ => throw const FormatException('Unknown conditional order kind'),
      };
}

class TxMarketConditionalOrder {
  TxMarketConditionalOrder({
    required this.id,
    required this.symbol,
    required this.side,
    required this.kind,
    required this.triggerPriceCents,
    required this.quantity,
    required this.createdGameDay,
    required this.createdMinuteOfDay,
  }) {
    if (id.trim().isEmpty || symbol.trim().isEmpty) {
      throw ArgumentError('Conditional order id and symbol are required');
    }
    if (triggerPriceCents < 1) {
      throw ArgumentError.value(triggerPriceCents, 'triggerPriceCents');
    }
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    if (createdGameDay < 1 ||
        createdMinuteOfDay < 0 ||
        createdMinuteOfDay >= 1440) {
      throw ArgumentError('Invalid conditional order creation clock');
    }
  }

  final String id;
  final String symbol;
  final TxSide side;
  final TxMarketConditionalOrderKind kind;
  final int triggerPriceCents;
  final int quantity;
  final int createdGameDay;
  final int createdMinuteOfDay;

  /// Human-readable comparison used by the protection panel and audit row.
  String get triggerOperator {
    if (kind == TxMarketConditionalOrderKind.stopLoss) {
      return side == TxSide.sell ? '≤' : '≥';
    }
    return side == TxSide.sell ? '≥' : '≤';
  }

  /// Whether the latest durable mark has crossed this instruction.
  bool shouldTrigger(int markPriceCents) {
    if (markPriceCents < 1) return false;
    return switch (triggerOperator) {
      '≤' => markPriceCents <= triggerPriceCents,
      _ => markPriceCents >= triggerPriceCents,
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'symbol': symbol,
        'side': side.name,
        'kind': kind.nameForJson,
        'triggerPriceCents': triggerPriceCents,
        'quantity': quantity,
        'createdGameDay': createdGameDay,
        'createdMinuteOfDay': createdMinuteOfDay,
      };

  static TxMarketConditionalOrder fromJsonMap(Map<String, dynamic> data) {
    if (data['id'] is! String ||
        data['symbol'] is! String ||
        data['side'] is! String ||
        data['kind'] is! String ||
        data['triggerPriceCents'] is! int ||
        data['quantity'] is! int ||
        data['createdGameDay'] is! int ||
        data['createdMinuteOfDay'] is! int) {
      throw const FormatException('Invalid conditional order fields');
    }
    try {
      final side = TxSide.values.firstWhere(
        (value) => value.name == data['side'],
        orElse: () => throw const FormatException('Unknown conditional side'),
      );
      return TxMarketConditionalOrder(
        id: data['id'] as String,
        symbol: data['symbol'] as String,
        side: side,
        kind: TxMarketConditionalOrderKindLabel.fromJsonValue(data['kind']),
        triggerPriceCents: data['triggerPriceCents'] as int,
        quantity: data['quantity'] as int,
        createdGameDay: data['createdGameDay'] as int,
        createdMinuteOfDay: data['createdMinuteOfDay'] as int,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid conditional order: $error');
    }
  }
}
