import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/tx_market_hero.dart';
import '../lib/widgets/tx_terminal_status.dart';
import '../lib/widgets/tx_terminal_theme.dart';

void main() {
  test('dark theme uses shared primary and surface colors', () {
    final theme = TxTerminalTheme.dark();
    expect(theme.scaffoldBackgroundColor, TxTerminalColors.background);
    expect(theme.colorScheme.primary, TxTerminalColors.primary);
    expect(theme.cardTheme.color, TxTerminalColors.surface);
  });

  testWidgets('market hero shows indicative and committed prices distinctly',
      (tester) async {
    final seconds = ValueNotifier<double>(0.0);
    addTearDown(seconds.dispose);
    var buys = 0, sells = 0;
    await tester.pumpWidget(MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxMarketHero(symbol: 'SIM-A01', step: 1,
        committedPriceCents: 1000, seconds: seconds,
        indicativeCents: (s) => 1000.0 + s / 2,
        onBuy: () => buys++, onSell: () => sells++))));
    expect(find.text('¥10.0000'), findsOneWidget);
    expect(find.textContaining('已提交收盘 ¥10.00'), findsOneWidget);
    expect(find.text('OFFLINE · SIM'), findsOneWidget);
    seconds.value = 2.0;
    await tester.pump();
    expect(find.text('¥10.0100'), findsOneWidget);
    expect(find.textContaining('已提交收盘 ¥10.00'), findsOneWidget);
    await tester.tap(find.text('快捷买入'));
    await tester.tap(find.text('快捷卖出'));
    expect(buys, 1);
    expect(sells, 1);
  });

  testWidgets('paused and running state strip updates only displayed time',
      (tester) async {
    final seconds = ValueNotifier<double>(0.0);
    addTearDown(seconds.dispose);
    Widget app(bool running) => MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxTerminalStatus(seconds: seconds,
        step: 14, revision: 7, running: running, speed: 100, busy: false)));
    await tester.pumpWidget(app(false));
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('游戏分钟 14  ·  SQLite r7'), findsOneWidget);
    await tester.pumpWidget(app(true));
    expect(find.text('100×'), findsOneWidget);
    seconds.value = 12.0;
    await tester.pump();
    expect(find.text('游戏分钟 14  ·  SQLite r7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UI is usable at narrow phone width without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seconds = ValueNotifier<double>(0.0);
    addTearDown(seconds.dispose);
    await tester.pumpWidget(MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: Column(children: [
        TxTerminalStatus(seconds: seconds, step: 2,
          revision: 1, running: false, speed: 1, busy: false),
        TxMarketHero(symbol: 'SIM-A01', step: 2,
          committedPriceCents: 1000, seconds: seconds,
          indicativeCents: (s) => 1000.0,
          onBuy: () {}, onSell: () {}),
        const TxMetricTile(label: '可用现金', value: '¥100.00'),
      ])))));
    expect(tester.takeException(), isNull);
    expect(find.text('快捷买入'), findsOneWidget);
  });
}
