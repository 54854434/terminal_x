import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/tx_market_hero.dart';
import '../lib/widgets/tx_premium_ui.dart';
import '../lib/widgets/tx_terminal_status.dart';
import '../lib/widgets/tx_terminal_theme.dart';
import '../lib/widgets/tx_settings_page.dart';
import '../lib/widgets/tx_ticket_submit_bar.dart';
import '../lib/engine/tx_engine.dart';

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

  testWidgets('connected market hero identifies the executable Rust core',
      (tester) async {
    final seconds = ValueNotifier<double>(0.0);
    addTearDown(seconds.dispose);
    await tester.pumpWidget(MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxMarketHero(symbol: 'SIM-A01', step: 1,
        committedPriceCents: 1000, seconds: seconds,
        indicativeCents: (_) => 1000.0,
        onBuy: () {}, onSell: () {}, coreConnected: true))));
    expect(find.text('RUST · 已连接'), findsOneWidget);
    expect(find.text('OFFLINE · SIM'), findsNothing);
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

  testWidgets('settlement state is visible without changing committed labels',
      (tester) async {
    final seconds = ValueNotifier<double>(59.999);
    final settling = ValueNotifier<bool>(false);
    final phase = ValueNotifier<double>(0.0);
    addTearDown(seconds.dispose);
    addTearDown(settling.dispose);
    addTearDown(phase.dispose);
    Widget app() => MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxTerminalStatus(seconds: seconds,
        step: 21, revision: 42, running: true, speed: 100, busy: false,
        settling: settling, settlementPhase: phase)));
    await tester.pumpWidget(app());
    expect(find.text('正在处理当前结算，未确认时间不会前进'), findsNothing);
    expect(find.text('游戏分钟 21  ·  SQLite r42'), findsOneWidget);
    settling.value = true;
    phase.value = .5;
    await tester.pump();
    expect(find.text('正在处理当前结算，未确认时间不会前进'), findsOneWidget);
    expect(find.text('游戏分钟 21  ·  SQLite r42'), findsOneWidget);
    settling.value = false;
    await tester.pump();
    expect(find.text('正在处理当前结算，未确认时间不会前进'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('intraminute sync is distinguished from SQLite settlement',
      (tester) async {
    final seconds = ValueNotifier<double>(15.0);
    final settling = ValueNotifier<bool>(true);
    final pulse = ValueNotifier<bool>(true);
    final phase = ValueNotifier<double>(.25);
    addTearDown(seconds.dispose);
    addTearDown(settling.dispose);
    addTearDown(pulse.dispose);
    addTearDown(phase.dispose);
    await tester.pumpWidget(MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxTerminalStatus(seconds: seconds,
        step: 4, revision: 8, running: true, speed: 600, busy: true,
        settling: settling, settlingPulse: pulse,
        settlementPhase: phase))));
    expect(find.text('正在同步真实盘口，未确认时间不会前进'), findsOneWidget);
    expect(find.text('正在处理当前结算，未确认时间不会前进'), findsNothing);
    pulse.value = false;
    settling.value = false;
    settling.value = true;
    await tester.pump();
    expect(find.text('正在同步真实盘口，未确认时间不会前进'), findsNothing);
    expect(find.text('正在处理当前结算，未确认时间不会前进'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending automatic save is visible without faking SQLite revision',
      (tester) async {
    final seconds = ValueNotifier<double>(0.0);
    addTearDown(seconds.dispose);
    await tester.pumpWidget(MaterialApp(theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxTerminalStatus(seconds: seconds,
        step: 4, revision: 12, running: true, speed: 5, busy: false,
        pendingSave: true, pendingOperations: 3,
        pendingGameMinutes: 3, automaticSaveMinutes: 5))));
    expect(find.text('游戏分钟 4  ·  SQLite r12'), findsOneWidget);
    expect(find.text('待保存 3 项 · 每 5 个游戏分钟自动保存'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
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

  testWidgets('settings page groups runtime market storage and diagnostics',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selectedSpeed = 100;
    await tester.pumpWidget(MaterialApp(
      theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxSettingsPage(
        appVersion: '0.3.5',
        rustStatus: 'ARM64 ABI v2 已绑定',
        ready: true,
        running: false,
        speed: selectedSpeed,
        actualMultiplier: '等待样本',
        pulseSeconds: 15,
        automaticSaveMinutes: 60,
        automaticSaveDraft: 60,
        checkpointInterval: 32,
        checkpointDraft: 32,
        currentRevision: 12,
        pendingSave: true,
        pendingOperations: 3,
        pendingGameMinutes: 3,
        storageSummary: 'SQLite 1.20 MiB · 12 份快照',
        onSpeedPreset: (value) => selectedSpeed = value,
      ))));
    expect(find.text('设置中心'), findsOneWidget);
    expect(find.text('实测提交速度'), findsOneWidget);
    await tester.tap(find.text('600×'));
    expect(selectedSpeed, 600);
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pump();
    expect(find.text('自动保存周期'), findsOneWidget);
    expect(find.textContaining('当前有 3 项待保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium workspace primitives keep hierarchy and explanation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TxTerminalTheme.dark(),
      home: Scaffold(body: ListView(children: const [
        TxPageHeader(
          icon: Icons.candlestick_chart,
          eyebrow: 'MARKET DESK',
          title: '行情',
          subtitle: '价格、盘口与成交',
          status: '真实撮合',
        ),
        TxSectionHeader(
          title: '盘口',
          subtitle: '只读可见挂单',
          icon: Icons.info_outline,
        ),
        TxInfoStrip(
          icon: Icons.info_outline,
          text: '说明文字',
        ),
      ])),
    ));
    expect(find.text('MARKET DESK'), findsOneWidget);
    expect(find.text('行情'), findsOneWidget);
    expect(find.text('真实撮合'), findsOneWidget);
    expect(find.text('只读可见挂单'), findsOneWidget);
    expect(find.text('说明文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order submit bar exposes the selected limit policy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TxTerminalTheme.dark(),
      home: Scaffold(body: TxTicketSubmitBar(
        side: TxSide.buy, isLimit: true,
        timeInForce: TxTimeInForce.postOnly,
        enabled: true, onReview: () {}),
      ),
    ));
    expect(find.text('限价'), findsOneWidget);
    expect(find.textContaining('Post Only'), findsOneWidget);
    expect(find.text('检查并买入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
