import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';

void main() {
  test('new session: price-time book, 100-share buy and 50-share sell', () {
    final s = TxSession.fresh();
    final cash = s.engine.account(TxSession.playerId).cashCents;
    final buy = s.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.market, quantity: 100);
    expect(buy.status, TxStatus.filled);
    expect(s.engine.account(TxSession.playerId).sharesOf(TxSession.symbols[0]), 100);
    expect(s.engine.account(TxSession.playerId).cashCents, cash - 100 * 1001);
    final sell = s.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.sell, kind: TxKind.market, quantity: 50);
    expect(sell.status, TxStatus.filled);
    expect(s.engine.account(TxSession.playerId).sharesOf(TxSession.symbols[0]), 50);
    expect(s.engine.fills.length, 2);
    s.engine.checkInvariants();
  });

  test('resting limit freezes cash, survives reload, cancel releases', () {
    final s = TxSession.fresh();
    final order = s.placePlayer(symbol: TxSession.symbols[0],
        side: TxSide.buy, kind: TxKind.limit, quantity: 50,
        limitPriceCents: 800);
    expect(order.status, TxStatus.open);
    expect(s.engine.account(TxSession.playerId).reservedCashCents, 40000);
    final reloaded = TxSession.importJson(s.exportJson());
    expect(reloaded.engine.depth(TxSession.symbols[0], TxSide.buy).isNotEmpty, isTrue);
    reloaded.cancelPlayer(order.id);
    expect(reloaded.engine.account(TxSession.playerId).reservedCashCents, 0);
    reloaded.engine.checkInvariants();
  });

  test('low liquidity crosses real levels, leftover market order cancels', () {
    final s = TxSession.fresh();
    final result = s.placePlayer(symbol: TxSession.symbols[1],
        side: TxSide.buy, kind: TxKind.market, quantity: 300);
    expect(result.status, TxStatus.cancelled);
    expect(result.filled, 245);
    expect(result.remaining, 55);
    expect(s.engine.account(TxSession.playerId).sharesOf(TxSession.symbols[1]), 245);
    expect(s.engine.depth(TxSession.symbols[1], TxSide.sell), isEmpty);
    s.engine.checkInvariants();
  });

  test('deterministic ticks and save/restore preserve identical execution', () {
    final a = TxSession.fresh();
    final b = TxSession.fresh();
    a.nextTick();
    b.nextTick();
    expect(a.exportJson(), b.exportJson());
    final restored = TxSession.importJson(a.exportJson());
    a.nextTick();
    restored.nextTick();
    expect(a.exportJson(), restored.exportJson());
  });

  test('legacy migration retains settled funds, holdings, archival pending/trades', () {
    final legacy = jsonEncode({
      'cash': 999123.45,
      'prices': [10.05, 25.10],
      'owned': [100, 7],
      'step': 3,
      'pending': [
        {'symbol': 0, 'buy': true, 'qty': 50, 'limit': 9.9}
      ],
      'trades': ['买入 SIM-A01 100 股'],
    });
    final s = TxSession.fromLegacyJson(legacy);
    expect(s.isLegacyUpgrade, true);
    expect(s.engine.account(TxSession.playerId).cashCents, 99912345);
    expect(s.engine.account(TxSession.playerId).sharesOf(TxSession.symbols[0]), 100);
    expect(s.referenceCents, [1005, 2510]);
    expect(s.archivedLegacyOrders.length, 1);
    expect(s.archivedLegacyTrades.single, contains('SIM-A01'));
    expect(s.playerOrders, isEmpty);
    expect(TxSession.importJson(s.exportJson()).archivedLegacyOrders.length, 1);
    s.engine.checkInvariants();
  });

  test('invalid legacy save fails closed instead of resetting account', () {
    final legacy = jsonEncode({
      'cash': -1, 'prices': [10.00, 25.00], 'owned': [0, 0],
      'step': 0, 'pending': [], 'trades': [],
    });
    expect(() => TxSession.fromLegacyJson(legacy), throwsFormatException);
  });
}
