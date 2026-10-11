import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/tx_backup_commit.dart';
import 'engine/tx_backup_import.dart';
import 'engine/tx_engine.dart';
import 'engine/tx_session.dart';

void main() => runApp(const TerminalX());

class TerminalX extends StatelessWidget {
  const TerminalX({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Terminal X V0.1c',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0E121B),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B98FF),
            brightness: Brightness.dark,
          ),
        ),
        home: const TradingScreen(),
      );
}

class TradingScreen extends StatefulWidget {
  const TradingScreen({super.key});

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  final _qty = TextEditingController(text: '100');
  final _limit = TextEditingController(text: '10.00');
  TxSession? _session;
  int _selected = 0;
  bool _limitOrder = false;
  bool _loading = true;
  bool _importing = false;
  bool _hasImported = false;
  String? _storageError;
  String _message = 'V0.1c：独立安装；可安全导入 V0.1b XML 备份。';
  Future<void> _writeChain = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newSnapshot = prefs.getString(TxSession.saveKey);
      late final TxSession session;
      var migrated = false;
      if (newSnapshot != null) {
        session = TxSession.importJson(newSnapshot);
      } else {
        final legacy = prefs.getString(TxSession.oldSaveKey);
        if (legacy == null) {
          session = TxSession.fresh();
        } else {
          session = TxSession.fromLegacyJson(legacy);
          migrated = true;
        }
        final saved = await prefs.setString(TxSession.saveKey, session.exportJson());
        if (!saved) throw StateError('Initial session snapshot not written');
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
        _hasImported = prefs.containsKey(TxBackupCommit.preImportSaveKey);
        _limit.text = (session.referenceCents[0] / 100).toStringAsFixed(2);
        if (migrated) {
          _message = '已迁移旧现金/持仓/报价。旧挂单仅归档，不会自动继续成交；旧存档未修改。';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _storageError = '无法安全读取存档：$error。已停止交易，未覆盖原存档。';
      });
    }
  }

  // Order writes are serialized. Import waits for this queue and disables new
  // trades throughout file picking, user confirmation and commit.
  void _persist() {
    final snap = _session!.exportJson();
    _writeChain = _writeChain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(TxSession.saveKey, snap);
      if (!saved) throw StateError('shared_preferences refused the write');
    }).catchError((Object error) {
      if (mounted) {
        setState(() {
          _storageError = '保存失败：$error。为保护数据，已暂停进一步下单。';
        });
      }
    });
  }

  String _money(int cents) => (cents / 100).toStringAsFixed(2);
  bool get _canTrade => !_loading && !_importing &&
      _session != null && _storageError == null;

  // Only the selected file's bytes are read. No ADB, root permission or direct
  // access to V0.1b's private storage is needed. The source file is unchanged.
  Future<void> _importXmlBackup() async {
    if (!_canTrade || _hasImported) return;
    setState(() => _importing = true);
    var startedStorageCommit = false;
    try {
      await _writeChain;
      if (_storageError != null) throw StateError('Pending save failed');

      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        withData: true,
      );
      if (!mounted || selection == null) return;
      if (selection.files.length != 1) {
        throw const FormatException('Please select one XML backup');
      }
      final file = selection.files.single;
      if (file.size <= 0 || file.size > TxBackupImport.maxXmlCharacters) {
        throw const FormatException('Backup file is empty or too large');
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.length != file.size) {
        throw const FormatException('Could not read complete backup bytes');
      }
      final xml = utf8.decode(bytes, allowMalformed: false);
      final proposed = TxBackupImport.previewXml(xml);
      final player = proposed.engine.account(TxSession.playerId);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认导入 V0.1b 存档'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('交易引擎校验通过。请核对：'),
                const SizedBox(height: 8),
                Text('模拟时间：第 ${proposed.step} 步'),
                Text('现金：¥${_money(player.cashCents)}'),
                Text('冻结现金：¥${_money(player.reservedCashCents)}'),
                for (final symbol in TxSession.symbols)
                  Text('$symbol：${player.sharesOf(symbol)} 股；冻结 '
                      '${player.reservedSharesOf(symbol)} 股'),
                Text('玩家委托：${proposed.playerOrders.length} 笔'),
                Text('玩家成交：${proposed.playerFills.length} 笔'),
                const SizedBox(height: 12),
                const Text(
                  '确认后只替换本 V0.1c 的会话；替换前将保存 V0.1c 原会话副本。'
                  '原 V0.1b 应用及你在下载文件夹中的 XML 不会被修改。'
                  '为保护数据，本版本仅允许导入一次。',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await _writeChain;
      if (_storageError != null) throw StateError('Pending save failed');
      startedStorageCommit = true;
      final restored = await TxBackupCommit.commitOnce(proposed);
      if (!mounted) return;
      setState(() {
        _session = restored;
        _hasImported = true;
        _selected = 0;
        _limitOrder = false;
        _limit.text = _money(restored.referenceCents[0]);
        _message = '导入成功，已校验账务并保存。V0.1b 原应用与备份未修改。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (startedStorageCommit) {
          _storageError = '导入写入或验证失败，已暂停交易。'
              'V0.1c 原会话恢复副本仍受保护。不要清除应用数据。';
        } else {
          _message = '未导入：文件解析/校验失败，或者读取存档时出错。原数据未修改。';
        }
      });
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  int? _parsePrice(String value) {
    final amount = double.tryParse(value.trim());
    if (amount == null || !amount.isFinite || amount <= 0 ||
        amount * 100 > TxEngine.maxPriceCents) return null;
    final cents = (amount * 100).round();
    return cents >= 1 ? cents : null;
  }

  void _submit(TxSide side) {
    if (!_canTrade) return;
    final quantity = int.tryParse(_qty.text.trim());
    final price = _limitOrder ? _parsePrice(_limit.text) : null;
    if (quantity == null || quantity <= 0 ||
        (_limitOrder && price == null)) {
      setState(() => _message = '请输入有效数量和限价。');
      return;
    }
    try {
      final order = _session!.placePlayer(
        symbol: TxSession.symbols[_selected],
        side: side,
        kind: _limitOrder ? TxKind.limit : TxKind.market,
        quantity: quantity,
        limitPriceCents: price,
      );
      setState(() {
        _message = order.status == TxStatus.rejected
            ? '拒单：${order.rejectReason}'
            : '委托 ${order.id}：成交 ${order.filled} 股，剩余 ${order.remaining} 股；${_status(order.status)}';
      });
      _persist();
    } catch (error) {
      setState(() => _message = '下单失败：$error');
    }
  }

  void _cancel(TxOrder order) {
    if (!_canTrade) return;
    try {
      _session!.cancelPlayer(order.id);
      setState(() => _message = '已撤销 ${order.id}，剩余冻结金额/持仓已释放。');
      _persist();
    } catch (error) {
      setState(() => _message = '撤单失败：$error');
    }
  }

  void _nextTick() {
    if (!_canTrade) return;
    try {
      _session!.nextTick();
      setState(() => _message = '模拟时间：第 ${_session!.step} 步；有限流动性重新报价。');
      _persist();
    } catch (error) {
      setState(() => _message = '推进行情失败：$error');
    }
  }

  String _status(TxStatus status) {
    switch (status) {
      case TxStatus.open:
        return '挂单中';
      case TxStatus.partiallyFilled:
        return '部分成交';
      case TxStatus.filled:
        return '全部成交';
      case TxStatus.cancelled:
        return '已取消/未成交余量取消';
      case TxStatus.rejected:
        return '拒绝';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TERMINAL X · 存档保护')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SelectableText(_storageError ?? '无法读取存档'),
        ),
      );
    }
    final session = _session!;
    final player = session.engine.account(TxSession.playerId);
    final symbol = TxSession.symbols[_selected];
    final asks = session.engine.depth(symbol, TxSide.sell).reversed.toList();
    final bids = session.engine.depth(symbol, TxSide.buy);
    final orders = session.playerOrders;
    final active = orders.where((o) =>
        o.status == TxStatus.open || o.status == TxStatus.partiallyFilled).toList();
    final recent = session.playerFills.take(8).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('TERMINAL X · V0.1c'),
        actions: [IconButton(
          icon: const Icon(Icons.skip_next),
          tooltip: '推进行情',
          onPressed: _canTrade ? _nextTick : null,
        )],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('V0.1b 存档安全导入',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('从手机下载文件夹选择备份 XML。先只读校验并预览，'
                    '你确认后才会写入独立的 V0.1c 数据区。'),
                const SizedBox(height: 8),
                if (_hasImported)
                  const Text('此设备的 V0.1c 已使用过导入功能；'
                      '为防止覆盖现有数据，不允许再次导入。'),
                if (_importing) const LinearProgressIndicator(),
                FilledButton.icon(
                  onPressed: (_canTrade && !_hasImported) ? _importXmlBackup : null,
                  icon: const Icon(Icons.folder_open),
                  label: Text(_hasImported ? '存档已导入' : '选择 XML 并预览'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('总资产 ¥${_money(session.totalAssetsCents)}',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        Text('现金 ¥${_money(player.cashCents)}  ·  可用 ¥${_money(player.availableCashCents)}'),
        Text('冻结资金 ¥${_money(player.reservedCashCents)}  ·  第 ${session.step} 步',
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 14),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('SIM-A01')),
            ButtonSegment(value: 1, label: Text('SIM-A02')),
          ],
          selected: {_selected},
          onSelectionChanged: _canTrade ? (values) => setState(() {
            _selected = values.first;
            _limit.text = _money(session.referenceCents[_selected]);
          }) : null,
        ),
        const SizedBox(height: 16),
        Text('¥${_money(session.lastPrice(symbol))}',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        Text('持仓 ${player.sharesOf(symbol)} 股  ·  可卖 ${player.availableSharesOf(symbol)} 股',
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        const Text('真实有限五档盘口（已冻结的委托数量）',
            style: TextStyle(fontWeight: FontWeight.bold)),
        if (asks.isEmpty) const Text('卖盘暂无有效挂单'),
        for (final level in asks)
          Text('卖盘  ¥${_money(level.priceCents)}       ${level.quantity} 股',
              style: const TextStyle(color: Color(0xFFFA7676))),
        const Divider(),
        if (bids.isEmpty) const Text('买盘暂无有效挂单'),
        for (final level in bids)
          Text('买盘  ¥${_money(level.priceCents)}       ${level.quantity} 股',
              style: const TextStyle(color: Color(0xFF54D49B))),
        const SizedBox(height: 12),
        Row(children: [
          const Text('限价单'),
          Switch(value: _limitOrder, onChanged: _canTrade
              ? (v) => setState(() => _limitOrder = v) : null),
          Expanded(child: TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '数量（股）'),
          )),
        ]),
        if (_limitOrder) TextField(
          controller: _limit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '限价'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: _canTrade ? () => _submit(TxSide.buy) : null,
            child: const Text('买入'),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(
            onPressed: _canTrade ? () => _submit(TxSide.sell) : null,
            child: const Text('卖出'),
          )),
        ]),
        OutlinedButton.icon(
          onPressed: _canTrade ? _nextTick : null,
          icon: const Icon(Icons.fast_forward),
          label: const Text('推进行情一步'),
        ),
        Text(_storageError ?? _message,
            style: TextStyle(color: _storageError == null
                ? Colors.amberAccent : Colors.redAccent)),
        if (session.isLegacyUpgrade)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('旧版资产已迁移；旧挂单不会自动执行，原存档保留。',
                style: TextStyle(color: Colors.orangeAccent)),
          ),
        const SizedBox(height: 14),
        Text('当前挂单（${active.length}）',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (active.isEmpty) const Text('暂无玩家挂单'),
        for (final order in active)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${order.side == TxSide.buy ? '买' : '卖'} ${order.symbol} '
                '${order.remaining}/${order.quantity}股 @ ¥${_money(order.limitPriceCents!)}'),
            subtitle: Text('${order.id} · ${_status(order.status)}'),
            trailing: IconButton(
              tooltip: '撤单',
              icon: const Icon(Icons.close),
              onPressed: _canTrade ? () => _cancel(order) : null,
            ),
          ),
        const SizedBox(height: 12),
        const Text('最近成交（真实撮合）', style: TextStyle(fontWeight: FontWeight.bold)),
        if (recent.isEmpty) const Text('暂无玩家成交'),
        for (final fill in recent)
          Text('${session.engine.order(fill.buyOrderId).ownerId == TxSession.playerId ? '买入' : '卖出'} '
              '${fill.symbol} ${fill.quantity}股 @ ¥${_money(fill.priceCents)}'),
        const SizedBox(height: 12),
        const Text('最近委托状态', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final order in orders.take(8))
          Text('${order.id} · ${_status(order.status)} · 已成交 ${order.filled}/${order.quantity}'),
        if (session.archivedLegacyOrders.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('旧版待处理挂单归档（${session.archivedLegacyOrders.length}，未激活）'),
          for (final order in session.archivedLegacyOrders.take(10))
            Text(order.toString(), style: const TextStyle(color: Colors.white54)),
        ],
        if (session.archivedLegacyTrades.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('旧版历史成交记录（仅供查看）'),
          for (final entry in session.archivedLegacyTrades.take(8))
            Text(entry, style: const TextStyle(color: Colors.white54)),
        ],
        const SizedBox(height: 36),
        const Text('本地合成股票与有限资金/库存做市商。未实现正式交易所规则、手续费、SQLite或生产签名。'
            'V0.1c 与 V0.1b 分属独立应用。',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
