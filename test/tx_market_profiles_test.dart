import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/market/tx_market_profiles.dart';
import '../lib/widgets/tx_market_mode_selector.dart';
import '../lib/widgets/tx_market_mode_preview_card.dart';

void main() {
  test('all five market modes have explicit rule metadata', () {
    expect(TxMarketProfile.values.length, 5);
    expect(TxMarketProfile.of(TxMarketMode.aShare).isCoreConnected, isTrue);
    for (final mode in TxMarketMode.values) {
      final profile = TxMarketProfile.of(mode);
      expect(profile.label, isNotEmpty);
      expect(profile.category, isNotEmpty);
      expect(profile.session, isNotEmpty);
      expect(profile.orderUnit, isNotEmpty);
      expect(profile.coreStatus, isNotEmpty);
      expect(profile.independentCoreProgress, inInclusiveRange(0.0, 1.0));
      if (!profile.isCoreConnected) {
        expect(profile.independentCoreProgress, 0.92);
      }
      expect(profile.instruments, isNotEmpty);
      expect(profile.instruments.map((item) => item.symbol).toSet().length,
          profile.instruments.length);
      expect(profile.instruments.every((item) => item.coreConnected),
          profile.isCoreConnected);
      for (final instrument in profile.instruments) {
        expect(instrument.quoteCurrency, profile.quoteCurrency);
        expect(instrument.orderUnit, isNotEmpty);
        expect(instrument.tickSize, isNotEmpty);
        expect(instrument.contractMultiplierUnits, greaterThan(0));
      }
    }
    expect(TxMarketProfile.aShare.instruments.map((item) => item.symbol)
        .toList(),
        ['SIM-A01', 'SIM-A02']);
  });

  testWidgets('market mode selector exposes five honest profiles',
      (tester) async {
    var selected = TxMarketMode.aShare;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        StatefulBuilder(builder: (context, setState) => TxMarketModeSelector(
          selected: selected,
          onSelected: (mode) => setState(() => selected = mode),
        )))));

    for (final label in ['A股', '美股', '期货', '虚拟货币', '外汇']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('期货'));
    await tester.pump();
    expect(selected, TxMarketMode.futures);
    expect(find.textContaining('规则层、风控、撮合、快照、费率'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconnected mode preview never re-labels an A-share ledger',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TxMarketModePreviewCard(profile: TxMarketProfile.futures))));

    expect(find.text('期货 · 规则预览'), findsOneWidget);
    expect(find.textContaining('不会复用 A 股现货账本'), findsOneWidget);
    expect(find.text('未接入'), findsOneWidget);
    expect(find.textContaining('SIM-FUT01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
