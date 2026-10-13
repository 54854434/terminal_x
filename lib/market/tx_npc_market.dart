/// Funded, deterministic background counterparties. All prints and volume
/// originate from TxEngine orders and ordinary price-time matching.
/// This batch adds inventory-aware liquidity and finite risk budgets; economic
/// Pulse events can now be committed within a minute at a chosen cadence;
/// they are actual Rust-backed orders, never rendered fake depth.
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

  /// Revise only resting NPC quotes. PLAYER orders remain on the FIFO book.
  static void cancelResting(TxEngine engine) {
    if (!isEnabled(engine)) return;
    // The active-only index avoids scanning years of archived NPC orders.
    // Preserve the original global sequence order for deterministic ledgers.
    final pending = engine.activeOrders.where((o) =>
        isNpc(o.ownerId) && o.kind == TxKind.limit &&
        o.timeInForce.canRest).toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final order in pending) {
      engine.cancel(order.id, ownerId: order.ownerId);
    }
  }

  static int _mix(int minute, int symbolIndex, int salt) {
    var h = (minute * 1103515245 + symbolIndex * 123457 + salt * 2654435761)
        & 0x7fffffff;
    h ^= (h >> 11);
    h = (h * 48271) & 0x7fffffff;
    return h;
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;

  /// Market maker's skew reflects its OWN finite inventory, never knowledge
  /// of the player's future actions. Zero inventory cannot offer fake asks.
  static void _placePassive(TxEngine engine, int minute, int index,
      String symbol, int reference, int movement) {
    final owner = engine.account('NPC_LIQ');
    final initialShares = index == 0 ? 4000 : 1400;
    final inventory = owner.sharesOf(symbol);
    final stress = movement.abs();
    // Spreads widen when the reference process becomes volatile. LP_A/LP_B
    // still supply their independently funded resting depth.
    final halfSpread = 1 + _min(6, stress ~/ 5);
    final bid = reference - halfSpread;
    final ask = reference + halfSpread + 1;
    final base = 15 + _mix(minute, index, 10) % 18;
    // Rebalance inventory toward the initial target with asymmetric quotes.
    final bidScale = inventory < initialShares ~/ 2 ? 2 : 1;
    final askScale = inventory > initialShares * 3 ~/ 2 ? 2 : 1;
    if (bid > 0 && bid <= TxEngine.maxPriceCents) {
      final affordable = owner.availableCashCents ~/ bid;
      final qty = _min(base * bidScale, affordable);
      if (qty > 0) {
        engine.place(
          id: 'NPC-L-$minute-$index-B', ownerId: 'NPC_LIQ',
          symbol: symbol, side: TxSide.buy, kind: TxKind.limit,
          quantity: qty, limitPriceCents: bid,
        );
      }
    }
    if (ask <= TxEngine.maxPriceCents) {
      final qty = _min(base * askScale, owner.availableSharesOf(symbol));
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
      String symbol, String agent, TxSide side, int salt, int movement) {
    final account = engine.account(agent);
    final opposing = engine.depth(symbol,
        side == TxSide.buy ? TxSide.sell : TxSide.buy, levels: 8);
    if (opposing.isEmpty) return;
    final visibleQty = opposing.fold<int>(0, (sum, level) => sum + level.quantity);
    // Aggressive NPCs use price-protected IOC limits. They can take visible
    // liquidity and suffer partial fills, but cannot silently sweep an
    // unbounded price tail. This gives trend/value/flow agents different
    // execution behaviour while keeping every fill funded and auditable.
    final baseline = index == 0 ? 18 : 8;
    final randomness = index == 0 ? 120 : 40;
    var desired = baseline + _mix(minute, index, salt) % randomness;
    // Trend traders enlarge urgency in volatile periods, value traders scale
    // down risk, and order-flow traders retain independent stochastic intent.
    if (agent == 'NPC_TREND') {
      desired += _min(45, movement.abs() * 2);
    } else if (agent == 'NPC_VALUE') {
      desired = _max(1, desired - _min(25, movement.abs()));
    }
    var quantity = _min(desired, visibleQty);
    final best = opposing.first.priceCents;
    final worst = opposing.last.priceCents;
    final protection = switch (agent) {
      'NPC_TREND' => _min(8, 1 + movement.abs() ~/ 3),
      'NPC_VALUE' => 0,
      _ => 2,
    };
    final protectedPrice = agent == 'NPC_VALUE'
        ? best
        : side == TxSide.buy
            ? _min(TxEngine.maxPriceCents, worst + protection)
            : _max(1, worst - protection);
    if (side == TxSide.sell) {
      quantity = _min(quantity, account.availableSharesOf(symbol));
    } else {
      if (protectedPrice <= 0) return;
      quantity = _min(quantity, account.availableCashCents ~/ protectedPrice);
    }
    if (quantity <= 0) return;
    engine.place(
      id: 'NPC-M-$minute-$index-$salt', ownerId: agent,
      symbol: symbol, side: side, kind: TxKind.limit,
      quantity: quantity, limitPriceCents: protectedPrice,
      timeInForce: TxTimeInForce.ioc,
    );
  }

  /// Runs after funded LP quotes have been submitted. All changes are real
  /// order entries/cancels/matches, but V0.2.5 still uses one minute boundary.
  static void tradeMinute(TxEngine engine, int minute,
      List<String> symbols, List<int> references, List<int> movements) {
    if (!isEnabled(engine)) return; // Legacy session compatibility.
    if (symbols.length != references.length ||
        symbols.length != movements.length) {
      throw ArgumentError('Inconsistent NPC market symbol arrays');
    }
    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      final move = movements[i];
      _placePassive(engine, minute, i, symbol, references[i], move);
      final trendSide = move >= 0 ? TxSide.buy : TxSide.sell;
      _aggressive(engine, minute, i, symbol, 'NPC_TREND',
          trendSide, 21, move);
      _aggressive(engine, minute, i, symbol, 'NPC_VALUE',
          trendSide == TxSide.buy ? TxSide.sell : TxSide.buy, 22, move);
      final noiseSide = _mix(minute, i, 23).isEven ? TxSide.buy : TxSide.sell;
      _aggressive(engine, minute, i, symbol, 'NPC_FLOW',
          noiseSide, 23, move);
    }
    // Every place/cancel validates all invariants. TxSession.nextTick also
    // validates at the transaction boundary; avoid a duplicate full scan.
  }
}
