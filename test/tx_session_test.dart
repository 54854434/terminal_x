import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';
import '../lib/engine/tx_backup_import.dart';

void main() {
  test('R41 live price cache advances with fills and resets at minute boundary', () {
    final session = TxSession.fresh();
    const symbolA = 'SIM-A01';
    const symbolB = 'SIM-A02';
    expect(session.lastPrice(symbolA), 1000);
    expect(session.lastPrice(symbolB), 2500);
    // A second read at the same revision is observationally identical.
    expect(session.lastPrice(symbolA), 1000);
    final buy = session.placePlayer(symbol: symbolA, side: TxSide.buy,
        kind: TxKind.market, quantity: 1);
    expect(buy.status, TxStatus.filled);
    expect(session.lastPrice(symbolA), 1001);
    expect(session.lastPrice(symbolB), 2500);
    session.placePlayer(symbol: symbolB, side: TxSide.buy,
        kind: TxKind.market, quantity: 1);
    expect(session.lastPrice(symbolB), 2501);
    expect(session.lastPrice(symbolA), 1001);
    final saved = session.exportJson();
    final restored = TxSession.importJson(saved);
    expect(restored.exportJson(), saved);
    expect(restored.lastPrice(symbolA), session.lastPrice(symbolA));
    expect(restored.lastPrice(symbolB), session.lastPrice(symbolB));
    session.nextTick();
    // Any old-minute fills are no longer considered for the current quote.
    expect(session.lastPrice(symbolA), session.referenceCents[0]);
    expect(session.lastPrice(symbolB), session.referenceCents[1]);
  });

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

  group('V0.1c read-only Android XML backup preview', () {
    String xmlWith(String snapshot,
        {String key = 'flutter.terminal_x_v01b_state'}) {
      // Escape text exactly as Android SharedPreferences XML does.
      final escaped = snapshot
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;');
      return '<?xml version="1.0" encoding="utf-8"?>'
          '<map><string name="$key">$escaped</string></map>';
    }

    test('valid prefixed key reads a fresh session without touching storage', () {
      final original = TxSession.fresh();
      original.placePlayer(
          symbol: TxSession.symbols[0],
          side: TxSide.buy,
          kind: TxKind.market,
          quantity: 100);
      final restored = TxBackupImport.previewXml(xmlWith(original.exportJson()));
      expect(restored.exportJson(), original.exportJson());
      restored.engine.checkInvariants();
    });

    test('old unprefixed key and XML escaped content are accepted', () {
      final s = TxSession.fresh();
      final xml = xmlWith(s.exportJson(),
          key: TxSession.saveKey)
          .replaceFirst('</map>', '<string name="other">A&amp;B</string></map>');
      expect(TxBackupImport.previewXml(xml).exportJson(), s.exportJson());
    });

    test('valid open limit order preserves frozen cash', () {
      final s = TxSession.fresh();
      s.placePlayer(
          symbol: TxSession.symbols[0],
          side: TxSide.buy,
          kind: TxKind.limit,
          quantity: 50,
          limitPriceCents: 800);
      final restored = TxBackupImport.previewXml(xmlWith(s.exportJson()));
      expect(
          restored.engine.account(TxSession.playerId).reservedCashCents,
          40000);
    });

    test('missing V0.1b key fails closed', () {
      final xml = '<map><string name="flutter.terminal_state">'
          'not a V0.1b snapshot</string></map>';
      expect(() => TxBackupImport.previewXml(xml), throwsFormatException);
    });

    test('duplicate V0.1b keys fail closed', () {
      final s = TxSession.fresh().exportJson();
      final first = xmlWith(s);
      final duplicate = first.replaceFirst(
          '</map>',
          '<string name="${TxSession.saveKey}">$s</string></map>');
      expect(() => TxBackupImport.previewXml(duplicate), throwsFormatException);
    });

    test('corrupted session JSON fails without reset', () {
      expect(() => TxBackupImport.previewXml(xmlWith('{"schema":1')),
          throwsFormatException);
    });

    test('tampered account cash fails the engine ledger invariant', () {
      final data = jsonDecode(TxSession.fresh().exportJson())
          as Map<String, dynamic>;
      final engine = jsonDecode(data['engine'] as String)
          as Map<String, dynamic>;
      final accounts = engine['accounts'] as List;
      final player = (accounts.cast<Map<String, dynamic>>()
          .singleWhere((e) => e['id'] == TxSession.playerId));
      player['cashCents'] = (player['cashCents'] as int) + 1;
      data['engine'] = jsonEncode(engine);
      expect(() => TxBackupImport.previewXml(xmlWith(jsonEncode(data))),
          throwsFormatException);
    });

    test('DTD or malformed XML fails closed', () {
      final s = TxSession.fresh().exportJson();
      expect(() => TxBackupImport.previewXml(
          '<!DOCTYPE map [<!ENTITY x "bad">]>' + xmlWith(s)),
          throwsFormatException);
      expect(() => TxBackupImport.previewXml('<map><string>'),
          throwsFormatException);
    });
  });
}
