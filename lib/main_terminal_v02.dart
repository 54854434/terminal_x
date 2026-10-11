/// Terminal X V0.2 - batch-built, independent SQLite trading terminal.
///
/// Uses a NEW Android application ID, a fresh synthetic account and its own
/// private SQLite file. No preferences, legacy migrations or XML access.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'engine/tx_engine.dart';
import 'engine/tx_session.dart';
import 'market/tx_candle_history.dart';
import 'storage/tx_sqlite_store.dart';
import 'storage/tx_trading_service.dart';
import 'widgets/tx_candle_chart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TerminalXV02());
}

class TerminalXV02 extends StatelessWidget {
  const TerminalXV02({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Terminal X V0.2',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0D121D),
          cardTheme: const CardThemeData(
            color: Color(0xFF161F2D), margin: EdgeInsets.symmetric(vertical: 5),
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4F94F9),
            brightness: Brightness.dark,
          ),
        ),
        home: const TerminalHome(),
      );
}

class TerminalHome extends StatefulWidget {
  const TerminalHome({super.key});

  @override
  State<TerminalHome> createState() => _TerminalHomeState();
}

class _TerminalHomeState extends State<TerminalHome>
    with WidgetsBindingObserver {
  static const _up = Color(0xFF39CF9F);
  static const _down = Color(0xFFFF6878);

  final _quantity = TextEditingController(text: '1');
  final _limit = TextEditingController(text: '10.00');
  TxTradingService? _service;
  Future<void>? _pending;
  Timer? _timer;
  List<TxStoredSession> _history = [];
  int _tab = 0;
  int _symbolIndex = 0;
  int _speed = 1;
  bool _auto = false;
  bool _busy = false;
  bool _loading = true;
  bool _limitOrder = false;
  bool _showFills = false;
  int _autoSteps = 0;
  String? _storageError;
  String _message = '正在打开独立 SQLite 账户';

  bool get _canTrade => !_loading && !_busy &&
      _service != null && !_service!.blocked && _storageError == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No hidden trading while the user is away or Android backgrounds the app.
    if (state != AppLifecycleState.resumed) {
      _pauseAuto();
    }
  }

  void _pauseAuto() {
    _timer?.cancel();
    _timer = null;
    if (mounted && _auto) setState(() => _auto = false);
  }

  void _restartAutoTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_auto || _storageError != null || _service == null) return;
    // 1x=5 s, 5x=1 s, 10x=0.5 s. The timer skips when SQLite is busy.
    _timer = Timer.periodic(Duration(milliseconds: 5000 ~/ _speed), (_) {
      if (_canTrade) _nextStep(automated: true);
    });
  }

  void _toggleAuto() {
    if (!_canTrade) return;
    setState(() {
      _auto = !_auto;
      if (_auto) _autoSteps = 0;
    });
    _restartAutoTimer();
  }

  Future<void> _open() async {
    TxTradingService? trader;
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/terminal_x_v02.sqlite');
      trader = TxTradingService(TxSqliteStore(
        NativeDatabase.createInBackground(file),
      ));
      final loaded = await trader.open();
      final history = await trader.database.readHistory(limit: 160);
      if (!mounted) {
        await trader.close();
        return;
      }
      setState(() {
        _service = trader;
        _history = history;
        _limit.text = _money(loaded.session.lastPrice(TxSession.symbols[0]));
        _message = 'SQLite 已校验 · 修订 ${loaded.revision} · ${loaded.session.step} 步';
        _loading = false;
      });
    } catch (error) {
      await trader?.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _storageError = 'SQLite 存档校验失败：$error。为保护已有数据，'
            '交易已停用，未清除或重建数据库。';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _quantity.dispose();
    _limit.dispose();
    final operation = _pending;
    if (operation == null) {
      _service?.close();
    } else {
      operation.whenComplete(() async => _service?.close());
    }
    super.dispose();
  }

  String _money(int cents) => (cents / 100).toStringAsFixed(2);

  int? _priceCents(String raw) {
    // Accept only values expressible exactly to 2 decimal places.
    final text = raw.trim();
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;
    final frac = parts.length == 2
        ? int.tryParse(parts[1].padRight(2, '0')) : 0;
    if (frac == null) return null;
    final cents = whole * 100 + frac;
    return cents >= 1 && cents <= TxEngine.maxPriceCents ? cents : null;
  }

  String _status(TxStatus value) {
    switch (value) {
      case TxStatus.open: return '挂单中';
      case TxStatus.partiallyFilled: return '部分成交';
      case TxStatus.filled: return '已成交';
      case TxStatus.cancelled: return '已撤销 / 余量取消';
      case TxStatus.rejected: return '已拒单';
    }
  }

  // All operations are copy-on-write: the UI state advances ONLY after
  // SQLite commits, and failures disable later operations until safe reopen.
  void _operate(Future<String> Function(TxTradingService) operation) {
    if (!_canTrade) return;
    setState(() => _busy = true);
    _pending = _execute(operation);
  }

  Future<void> _execute(
      Future<String> Function(TxTradingService) operation) async {
    try {
      final message = await operation(_service!);
      // The trade may already be committed if history verification fails.
      // Never report it as an uncommitted order: stop and preserve the DB.
      List<TxStoredSession> history;
      try {
        history = await _service!.database.readHistory(limit: 160);
      } catch (error) {
        if (mounted) {
          setState(() => _storageError =
              '交易已提交但历史快照校验失败，已停止后续交易：$error');
          _pauseAuto();
        }
        return;
      }
      if (mounted) setState(() {
        _history = history;
        _message = message;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          if (_service!.blocked) {
            _storageError = 'SQLite 保存失败，已暂停交易：$error';
          } else {
            _message = '操作未完成：$error';
          }
        });
        if (_storageError != null) _pauseAuto();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit(TxSide side) {
    if (!_canTrade) return;
    final quantity = int.tryParse(_quantity.text.trim());
    final price = _limitOrder ? _priceCents(_limit.text) : null;
    if (quantity == null || quantity <= 0 || quantity > TxEngine.maxQuantity ||
        (_limitOrder && price == null)) {
      setState(() => _message = '请输入合法股数及最多两位小数的限价');
      return;
    }
    final symbol = TxSession.symbols[_symbolIndex];
    _operate((service) async {
      final order = await service.place(
        symbol: symbol, side: side,
        kind: _limitOrder ? TxKind.limit : TxKind.market,
        quantity: quantity, limitPriceCents: price,
      );
      return '${order.id} · 成交 ${order.filled} 股 · '
          '余量 ${order.remaining} 股 · ${_status(order.status)}';
    });
  }

  void _cancel(String id) => _operate((trader) async {
        await trader.cancel(id);
        return '$id 已撤销，相关冻结已释放';
      });

  void _nextStep({bool automated = false}) => _operate((trader) async {
        final stored = await trader.nextTick();
        if (automated) {
          _autoSteps++;
          // Until historical maker orders can be compacted, cap each
          // uninterrupted run to avoid aggressive disk growth at 10x.
          if (_autoSteps >= 60) _pauseAuto();
        }
        return '行情第 ${stored.session.step} 步 · SQLite 修订 ${stored.revision}'
            '${automated && !_auto ? ' · 已达单次自动步进上限' : ''}';
      });

  Widget _header(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              fontSize: 19, fontWeight: FontWeight.bold)),
          if (subtitle != null)
            Text(subtitle, style: const TextStyle(
                color: Colors.white60, fontSize: 12)),
        ]),
      );

  Widget _tileMetric(String label, String value, {Color? color}) =>
      SizedBox(width: 142, child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 17,
              fontWeight: FontWeight.w600, color: color)),
        ]),
      ));

  Widget _selectSymbol(TxSession session) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('SIM-A01')),
            ButtonSegment(value: 1, label: Text('SIM-A02')),
          ],
          selected: {_symbolIndex},
          onSelectionChanged: (values) => setState(() {
            _symbolIndex = values.first;
            _limit.text = _money(session.lastPrice(TxSession.symbols[_symbolIndex]));
          }),
        ),
      );

  Widget _depth(TxSession session, String symbol) {
    final sell = session.engine.depth(symbol, TxSide.sell);
    final buy = session.engine.depth(symbol, TxSide.buy);
    final maxQty = <int>[
      ...sell.map((l) => l.quantity), ...buy.map((l) => l.quantity), 1,
    ].reduce((a, b) => a > b ? a : b);

    Widget priceRow(String side, int price, int qty, Color color) => InkWell(
      onTap: () => setState(() {
        _limitOrder = true;
        _limit.text = _money(price);
        _tab = 1;
      }),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
        child: Stack(children: [
          FractionallySizedBox(
            widthFactor: qty / maxQty,
            child: Container(height: 21, color: color.withAlpha(35)),
          ),
          Row(children: [
            SizedBox(width: 44, child: Text(side,
                style: TextStyle(color: color, fontSize: 12))),
            Expanded(child: Text('¥${_money(price)}',
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
            Text('$qty 股', style: const TextStyle(fontSize: 12)),
          ]),
        ]),
      ),
    );

    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('五档真实委托盘口',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        for (var i = sell.length - 1; i >= 0; i--)
          priceRow('卖${i + 1}', sell[i].priceCents,
              sell[i].quantity, _down),
        const Divider(height: 12),
        for (var i = 0; i < buy.length; i++)
          priceRow('买${i + 1}', buy[i].priceCents,
              buy[i].quantity, _up),
        const SizedBox(height: 8),
        const Text('点击任一档价格可填入限价单',
            style: TextStyle(fontSize: 11, color: Colors.white54)),
      ]),
    ));
  }

  Widget _marketTab(TxSession session) {
    final symbol = TxSession.symbols[_symbolIndex];
    final candles = TxCandleHistory.fromSnapshots(_history, symbol);
    final price = session.lastPrice(symbol);
    final lastChange = candles.length >= 2
        ? price - candles[candles.length - 2].closeCents : 0;
    return ListView(padding: const EdgeInsets.all(14), children: [
      _selectSymbol(session),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(symbol, style: const TextStyle(color: Colors.white70)),
          Text('¥${_money(price)}', style: const TextStyle(
              fontSize: 34, fontWeight: FontWeight.bold)),
          Text('本步变化 ${lastChange >= 0 ? '+' : ''}${_money(lastChange)}',
              style: TextStyle(color: lastChange >= 0 ? _up : _down)),
        ],
      ))),
      Card(child: Padding(padding: const EdgeInsets.all(12),
          child: TxCandleChart(candles: candles))),
      _depth(session, symbol),
      _header('行情控制', subtitle: '仅前台运行，默认暂停；单次自动运行最多 60 步'),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(
        children: [
          Expanded(child: FilledButton.icon(
            onPressed: _canTrade ? _toggleAuto : null,
            icon: Icon(_auto ? Icons.pause : Icons.play_arrow),
            label: Text(_auto ? '暂停' : '运行'),
          )),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: _canTrade ? _nextStep : null,
              child: const Text('单步')),
          const SizedBox(width: 8),
          DropdownButton<int>(value: _speed,
            items: const [
              DropdownMenuItem(value: 1, child: Text('1×')),
              DropdownMenuItem(value: 5, child: Text('5×')),
              DropdownMenuItem(value: 10, child: Text('10×')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _speed = value);
              _restartAutoTimer();
            },
          ),
        ],
      ))),
      const SizedBox(height: 12),
      const Text('K 线按 SQLite 已保存的模拟步和实际成交聚合；'
          '不是外部市场价格，也不补造未记录的历史。',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]);
  }

  Widget _tradeTab(TxSession session) {
    final symbol = TxSession.symbols[_symbolIndex];
    final player = session.engine.account(TxSession.playerId);
    final asks = session.engine.depth(symbol, TxSide.sell);
    final bids = session.engine.depth(symbol, TxSide.buy);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _header('交易委托', subtitle: '限价、市价 · 严格按当前实际盘口撮合'),
      _selectSymbol(session),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            _tileMetric('可用现金', '¥${_money(player.availableCashCents)}'),
            _tileMetric('可卖持仓', '${player.availableSharesOf(symbol)} 股'),
            _tileMetric('卖一', asks.isEmpty ? '—' : '¥${_money(asks.first.priceCents)}', color: _down),
            _tileMetric('买一', bids.isEmpty ? '—' : '¥${_money(bids.first.priceCents)}', color: _up),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_limitOrder ? '限价委托' : '市价委托'),
            subtitle: const Text('市价单可能跨档成交并产生滑点'),
            value: _limitOrder,
            onChanged: _canTrade ? (value) => setState(() => _limitOrder = value) : null,
          ),
          TextField(controller: _quantity, enabled: _canTrade,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '股数', border: OutlineInputBorder())),
          if (_limitOrder) ...[
            const SizedBox(height: 10),
            TextField(controller: _limit, enabled: _canTrade,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '限价 ¥（最多两位小数）', border: OutlineInputBorder())),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _up,
                  foregroundColor: Colors.black),
              onPressed: _canTrade ? () => _submit(TxSide.buy) : null,
              child: const Text('买入'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _down,
                  foregroundColor: Colors.black),
              onPressed: _canTrade ? () => _submit(TxSide.sell) : null,
              child: const Text('卖出'),
            )),
          ]),
        ]),
      )),
      _header('活动委托', subtitle: '撤单后即时释放相应冻结资金或库存'),
      ..._activeOrderTiles(session),
    ]);
  }

  List<Widget> _activeOrderTiles(TxSession session) {
    final active = session.playerOrders.where((o) =>
        o.status == TxStatus.open ||
        o.status == TxStatus.partiallyFilled).toList();
    if (active.isEmpty) return [const ListTile(title: Text('暂无活动委托'))];
    return active.map((order) => Card(child: ListTile(
      dense: true,
      title: Text('${order.symbol} · ${order.side == TxSide.buy ? '买' : '卖'} '
          '${order.remaining}/${order.quantity} 股'),
      subtitle: Text('${order.id} · ¥${_money(order.limitPriceCents!)} · '
          '${_status(order.status)}'),
      trailing: IconButton(tooltip: '撤单', icon: const Icon(Icons.close),
        onPressed: _canTrade ? () => _cancel(order.id) : null),
    ))).toList();
  }

  Widget _assetsTab(TxSession session, TxStoredSession saved) {
    final account = session.engine.account(TxSession.playerId);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _header('账户与资产', subtitle: '金额均为整数分账务的显示换算'),
      Card(child: Padding(padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 6, children: [
          _tileMetric('总资产估值', '¥${_money(session.totalAssetsCents)}'),
          _tileMetric('现金余额', '¥${_money(account.cashCents)}'),
          _tileMetric('可用现金', '¥${_money(account.availableCashCents)}'),
          _tileMetric('冻结资金', '¥${_money(account.reservedCashCents)}'),
        ]),
      )),
      _header('持仓明细'),
      for (final symbol in TxSession.symbols)
        Card(child: ListTile(
          title: Text(symbol),
          subtitle: Text('持仓 ${account.sharesOf(symbol)} 股 · '
              '冻结 ${account.reservedSharesOf(symbol)} 股 · '
              '可卖 ${account.availableSharesOf(symbol)} 股'),
          trailing: Text('¥${_money(account.sharesOf(symbol) * session.lastPrice(symbol))}'),
        )),
      _header('数据库校验'),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SQLite 修订号：${saved.revision}'),
          Text('模拟步数：${session.step}'),
          Text('当前快照 SHA-256：${saved.sha256.substring(0, 16)}…'),
          const Text('提交前后都会执行资金、库存、冻结与成交账本校验。',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ))),
    ]);
  }

  Widget _historyTab(TxSession session) {
    final orders = session.playerOrders.take(100).toList();
    final fills = session.playerFills.take(100).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      _header('委托与成交历史', subtitle: '最多展示最近 100 条，完整账本保留在 SQLite 快照中'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('委托')),
          ButtonSegment(value: true, label: Text('成交')),
        ],
        selected: {_showFills},
        onSelectionChanged: (values) => setState(() => _showFills = values.first),
      ),
      if (!_showFills && orders.isEmpty) const ListTile(title: Text('暂无委托历史')),
      if (_showFills && fills.isEmpty) const ListTile(title: Text('暂无成交历史')),
      if (!_showFills)
        for (final order in orders)
          Card(child: ListTile(dense: true,
            title: Text('${order.id} · ${order.symbol} · '
                '${order.side == TxSide.buy ? '买' : '卖'} ${order.quantity} 股'),
            subtitle: Text('${_status(order.status)} · '
                '成交 ${order.filled} · 剩余 ${order.remaining}'),
            trailing: Text(order.limitPriceCents == null ? '市价' :
                '¥${_money(order.limitPriceCents!)}'),
          )),
      if (_showFills)
        for (final fill in fills)
          Card(child: ListTile(dense: true,
            title: Text('${fill.symbol} · '
                '${session.engine.order(fill.buyOrderId).ownerId == TxSession.playerId ? '买入' : '卖出'} '
                '${fill.quantity} 股'),
            subtitle: Text('成交记录 ${fill.id}'),
            trailing: Text('¥${_money(fill.priceCents)}'),
          )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Terminal X · 存档保护')),
        body: Padding(padding: const EdgeInsets.all(20),
          child: SelectableText(_storageError ?? '无法读取 SQLite 数据库')),
      );
    }

    final saved = _service!.current;
    final session = saved.session;
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TERMINAL X', style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 1)),
            Text('V0.2 · 离线交易终端',
                style: TextStyle(fontSize: 11, color: Colors.white60)),
          ]),
        actions: [
          IconButton(
            tooltip: _auto ? '暂停自动行情' : '运行自动行情',
            onPressed: _canTrade ? _toggleAuto : null,
            icon: Icon(_auto ? Icons.pause_circle : Icons.play_circle_outline),
          ),
          IconButton(tooltip: '手动推进行情',
            onPressed: _canTrade ? _nextStep : null,
            icon: const Icon(Icons.skip_next)),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF111B2A),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: Text('第 ${session.step} 步  ·  SQLite r${saved.revision}'
              '  ·  ${_auto ? '运行 $_speed×' : '已暂停'}',
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_storageError != null)
          Padding(padding: const EdgeInsets.all(10),
            child: SelectableText(_storageError!,
                style: const TextStyle(color: _down))),
        if (_storageError == null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(_message, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.amberAccent, fontSize: 12))),
        Expanded(child: switch (_tab) {
          0 => _marketTab(session),
          1 => _tradeTab(session),
          2 => _assetsTab(session, saved),
          _ => _historyTab(session),
        }),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.candlestick_chart), label: '行情'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: '交易'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: '资产'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: '记录'),
        ],
      ),
    );
  }
}
