/// Terminal X - isolated Android SQLite smoke probe.
///
/// This is a DIFFERENT Android application. It creates only synthetic demo
/// trading data in its own private SQLite database. It does not import or read
/// V0.1b/V0.1c preferences, XML backups, or any actual account data.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'engine/tx_engine.dart';
import 'engine/tx_session.dart';
import 'storage/tx_sqlite_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StorageProbeApp());
}

class StorageProbeApp extends StatelessWidget {
  const StorageProbeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        title: 'Terminal X SQLite Probe',
        home: const StorageProbeScreen(),
      );
}

class StorageProbeScreen extends StatefulWidget {
  const StorageProbeScreen({super.key});

  @override
  State<StorageProbeScreen> createState() => _StorageProbeScreenState();
}

class _StorageProbeScreenState extends State<StorageProbeScreen> {
  bool _running = false;
  String _outcome = '尚未执行。点击下方按钮，测试 Android 本地 SQLite。';

  TxSession _syntheticSession() {
    final session = TxSession.fresh();
    final buy = session.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.market,
      quantity: 2,
    );
    final resting = session.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.limit,
      quantity: 5,
      limitPriceCents: 800,
    );
    if (buy.filled != 2 || resting.status != TxStatus.open) {
      throw StateError('Synthetic order precondition failed');
    }
    session.engine.checkInvariants();
    return session;
  }

  Future<void> _runProbe() async {
    if (_running) return;
    setState(() {
      _running = true;
      _outcome = '正在验证本地数据库事务和关闭重开...';
    });

    TxSqliteStore? store;
    try {
      // getApplicationSupportDirectory is private to THIS isolated package.
      final directory = await getApplicationSupportDirectory();
      final dbFile = File('${directory.path}/terminal_x_probe.sqlite');
      store = TxSqliteStore(NativeDatabase.createInBackground(dbFile));

      var current = await store.readCurrent();
      final initialized = current == null;
      if (initialized) {
        final synthetic = _syntheticSession();
        current = await store.migrateFromPreferencesSnapshot(
          synthetic.exportJson(),
        );
      }
      if (current == null) throw StateError('Failed to initialize probe');

      // Each run tests a transaction without touching any real account.
      final advanced = TxSession.importJson(current.session.exportJson());
      advanced.nextTick();
      final written = await store.saveSession(
        advanced,
        expectedRevision: current.revision,
      );
      if (written.revision != current.revision + 1) {
        throw StateError('Unexpected saved revision');
      }

      // This is an actual file close/reopen, not just a re-read in memory.
      await store.close();
      store = null;
      store = TxSqliteStore(NativeDatabase.createInBackground(dbFile));
      final restored = await store.readCurrent();
      if (restored == null ||
          restored.revision != written.revision ||
          restored.sha256 != written.sha256 ||
          restored.session.exportJson() != advanced.exportJson()) {
        throw StateError('SQLite close/reopen validation failed');
      }
      restored.session.engine.checkInvariants();
      final player = restored.session.engine.account(TxSession.playerId);
      if (player.reservedCashCents != 4000 ||
          restored.session.playerFills.isEmpty ||
          restored.session.playerOrders.length != 2) {
        throw StateError('Cash freeze / order / fill verification failed');
      }
      if (!mounted) return;
      setState(() {
        _outcome = '通过：Android SQLite 已完成事务保存、关闭重开和 SHA-256/账务校验。\n'
            '测试数据：合成账户（非你的真实存档）\n'
            '数据库：本探针 App 私有目录\n'
            '初始创建：${initialized ? '是' : '否（复用已有测试库）'}\n'
            '存储修订号：${restored.revision}\n'
            '模拟步数：${restored.session.step}\n'
            '冻结资金：${player.reservedCashCents} 分\n'
            '持仓/委托/成交数据核对：通过\n'
            '摘要：${restored.sha256.substring(0, 16)}…';
      });
    } catch (error) {
      // A failed read is NOT repaired by resetting the database. Preserve it.
      if (mounted) {
        setState(() {
          _outcome = '未通过：$error\n探针数据库未被主动清除。'
              '旧 V0.1b / V0.1c App 及 XML 完全不受影响。';
        });
      }
    } finally {
      await store?.close();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('TERMINAL X · SQLite Probe')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'V0.1d · Android 存储探针（独立安装）',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const Text(
              '此 App 只创建合成测试账户，完全不读取或修改现有 '
              'V0.1b、V0.1c 的应用数据。绝不导入私人 XML。',
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _running ? null : _runProbe,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('执行 SQLite 实机验证'),
            ),
            if (_running) const LinearProgressIndicator(),
            const SizedBox(height: 22),
            SelectableText(_outcome),
            const SizedBox(height: 20),
            const Text(
              '测试项目：独立 Android SQLite 文件、内置 SQLite 原生库、'
              '事务提交、账务校验、冻结资金、持仓/委托/成交、SHA-256、'
              '关闭重开及再次执行。',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
}
