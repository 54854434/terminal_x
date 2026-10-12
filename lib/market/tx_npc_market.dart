/// Offline, deterministic background participants. All displayed fills come
/// from TxEngine, never from synthetic candles or manufactured tape data.
/// Accounts use finite cash and inventory and the ordinary reservation rules.
import '../engine/tx_engine.dart';

class TxNpcMarket {
  const TxNpcMarket._();

  static const participants = <String>[
    'NPC_TREND',
    'NPC_VALUE',
    'NPC_FLOW',
    'NPC_LIQ',
  ];

  static bool isNpc(String ownerId) => ownerId.startsWith('NPC_');

  static bool isEnabled(TxEngine engine) =>
      participants.every((id) => engine.accounts.containsKey(id));

  static void registerNewAccounts(TxEngine engine) {
    for (final id in participants) {
      engine.registerAccount(id, cashCents: 100000000, shares: const {
        'SIM-A01': 4000,
        'SIM-A02': 1400,
      });
    }
  }

  /// Cancel only the bot's own previous passive orders. Never touch PLAYER.
  static void cancelResting(TxEngine engine) {
    if (!isEnabled(engine)) return;
    final pending = engine.orders.values.where((o) =>
        isNpc(o.ownerId) && o.kind == TxKind.limit &&
        (o.status == TxStatus.open || o.status == TxStatus.partiallyFilled))
        .toList();
    for (final order in pending) {
      engine.cancel(order.id, ownerId: order.ownerId);
    }
  }

  static int _mix(int minute, int symbolIndex, int salt) {
    // No PRNG state to lose on app restart: same persisted minute => same
    // intent, provided the same real funded order book and participant assets.
    var h = (minute * 1103515245 + symbolIndex * 123457 + salt * 2654435761)
        & 0x7fffffff;
    h ^= (h >> 11);
    h = (h * 48271) & 0x7fffffff;
    return h;
  }

  static int _min(int a, int b) => a < b ? a : b;

  static void _placePassive(TxEngine engine, int minute, int index,
      String symbol, int reference) {
    final owner = engine.account('NPC_LIQ');
    final amount = 15 + _mix(minute, index, 10) % 18;
    final bid = reference;
    final ask = reference + 2;
    if (bid > 0 && bid <= TxEngine.maxPriceCents) {
      final affordable = owner.availableCashCents ~/ bid;
      final qty = _min(amount, affordable);
      if (qty > 0) {
        engine.place(
          id: 'NPC-L-$minute-$index-B', ownerId: 'NPC_LIQ',
          symbol: symbol, side: TxSide.buy, kind: TxKind.limit,
          quantity: qty, limitPriceCents: bid,
        );
      }
    }
    if (ask <= TxEngine.maxPriceCents) {
      final qty = _min(amount, owner.availableSharesOf(symbol));
      if (qty > 0) {
        engine.place(
          id: 'NPC-L-$minute-$index-S', ownerId: 'NPC_LIQ',
          symbol: symbol, side: TxSide.sell, kind: TxKind.limit,
          quantity: qty, limitPriceCents: ask,
        );
      }
    }
  }

  static void _aggressive(TxEngine engine, int minute, int index,
      String symbol, String agent, TxSide side, int salt) {
    final account = engine.account(agent);
    final opposing = engine.depth(symbol,
        side == TxSide.buy ? TxSide.sell : TxSide.buy);
    if (opposing.isEmpty) return; // No liquidity means no fictional fill.
    final availableQty = opposing.fold<int>(0, (a, b) => a + b.quantity);
    final desired = (index == 0 ? 18 : 8) + _mix(minute, index, salt) %
        (index == 0 ? 120 : 40);
    var quantity = _min(desired, availableQty);
    if (side == TxSide.sell) {
      quantity = _min(quantity, account.availableSharesOf(symbol));
    } else {
      // Conservative upper bound for a market sweep across all visible levels.
      final highestAsk = opposing.last.priceCents;
      if (highestAsk <= 0) return;
      quantity = _min(quantity, account.availableCashCents ~/ highestAsk);
    }
    if (quantity <= 0) return;
    engine.place(
      id: 'NPC-M-$minute-$index-$salt', ownerId: agent,
      symbol: symbol, side: side, kind: TxKind.market,
      quantity: quantity,
    );
  }

  /// Runs AFTER maker quotes for this minute. The passive participant posts
  /// funded orders; three other participants execute opposing market intents.
  /// Real trade prices and volumes are produced by the existing FIFO matcher.
  static void tradeMinute(TxEngine engine, int minute,
      List<String> symbols, List<int> references, List<int> movements) {
    if (!isEnabled(engine)) return; // Legacy save compatibility.
    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      _placePassive(engine, minute, i, symbol, references[i]);
      final trendSide = movements[i] >= 0 ? TxSide.buy : TxSide.sell;
      _aggressive(engine, minute, i, symbol, 'NPC_TREND', trendSide, 21);
      _aggressive(engine, minute, i, symbol, 'NPC_VALUE',
          trendSide == TxSide.buy ? TxSide.sell : TxSide.buy, 22);
      final noiseSide = _mix(minute, i, 23).isEven ? TxSide.buy : TxSide.sell;
      _aggressive(engine, minute, i, symbol, 'NPC_FLOW', noiseSide, 23);
    }
    engine.checkInvariants();
  }
}
