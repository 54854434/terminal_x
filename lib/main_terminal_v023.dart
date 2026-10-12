/// Terminal X V0.2.3 stable app-line active simulated-market preview.
/// Existing V0.2 + V0.1 apps and backups are never accessed.
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'engine/tx_engine.dart';
import 'engine/tx_session.dart';
import 'market/tx_live_candles.dart';
import 'market/tx_simulation_clock.dart';
import 'market/tx_realtime_clock.dart';
import 'storage/tx_sqlite_store.dart';
import 'storage/tx_trading_service.dart';
import 'widgets/tx_candle_chart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TerminalXV023());
}

class TerminalXV023 extends StatelessWidget {
  const TerminalXV023({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Terminal X',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0D121D),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F94F9), brightness: Brightness.dark),
      cardTheme: const CardThemeData(color: Color(0xFF161F2D)),
    ),
    home: const TerminalHomeV023(),
  );
}

class TerminalHomeV023 extends StatefulWidget {
  const TerminalHomeV023({super.key});
  @override
  State<TerminalHomeV023> createState() => _TerminalHomeV023State();
}

class _TerminalHomeV023State extends State<TerminalHomeV023>
    with WidgetsBindingObserver {
  static const green = Color(0xFF3DD3A5);
  static const red = Color(0xFFFF707A);
  static const appVersion = String.fromEnvironment('TX_APP_VERSION', defaultValue: '0.2.3');
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController(text: '10.00');
  TxTradingService? _trader;
  TxLiveCandles? _candles;
  Timer? _timer;
  Future<void>? _operation;
  int _page = 0;
  int _symbol = 0;
  int _speed = 1;
  int _autoCount = 0;
  int _fractionalSeconds = 0;
  bool _auto = false;
  bool _busy = false;
  bool _loading = true;
  bool _limit = false;
  int _recordMode = 0;
  String _notice = '正在检查 SQLite';
  String? _fault;

  bool get _ready => !_loading && !_busy && _fault == null &&
      _trader != null && !_trader!.blocked;
  String get _symbolName => TxSession.symbols[_symbol];
  String money(int cents) => (cents / 100).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (_auto && mounted) setState(() => _auto = false);
  }

  /// Exactly one real-time second per callback; each callback adds [speed]
  /// simulated seconds. Economic state advances only on complete game minutes.
  /// A slow SQLite commit pauses the scheduler rather than piling up ticks.
  void _scheduleNext() {
    _timer?.cancel();
    if (!_auto || !_ready) return;
    _timer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_auto || !_ready) return;
      final commits = TxRealtimeClock.minuteCommits(_fractionalSeconds, _speed);
      final remainder = TxRealtimeClock.remainderSeconds(_fractionalSeconds, _speed);
      if (commits == 0) {
        setState(() => _fractionalSeconds = remainder);
        _scheduleNext();
      } else {
        // The maximum allowed speed is 60x: at most one DB commit per second.
        _tick(automatic: true, remainderSeconds: remainder);
      }
    });
  }

  void _toggle() {
    if (!_ready) return;
    if (_auto) {
      _pause();
      return;
    }
    setState(() {
      _auto = true;
      _autoCount = 0;
    });
    _scheduleNext();
  }

  Future<void> _open() async {
    TxTradingService? service;
    try {
      final dir = await getApplicationSupportDirectory();
      final sqlite = File('${dir.path}/terminal_x_game.sqlite');
      service = TxTradingService(TxSqliteStore(
        NativeDatabase.createInBackground(sqlite)),
        initialSessionFactory: TxSession.freshWithAgents);
      final initial = await service.open();
      // Once, not on every committed tick. 64 recent revisions are enough to
      // reconstruct recent candles without loading the entire database.
      final recent = await service.database.readHistory(limit: 64);
      final candles = TxLiveCandles.fromVerifiedHistory(recent);
      if (!mounted) {
        await service.close();
        return;
      }
      setState(() {
        _trader = service;
        _candles = candles;
        _price.text = money(initial.session.lastPrice(_symbolName));
        _notice = '已校验 SQLite 修订 ${initial.revision}，行情默认暂停';
        _loading = false;
      });
    } catch (e) {
      await service?.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fault = 'SQLite 读取或校验失败，已停止交易并保留数据：$e';
      });
    }
  }

  void _operate(Future<String> Function(TxTradingService) work,
      {bool automated = false, int? remainderSeconds}) {
    if (!_ready) return;
    // While any step is outstanding, no additional scheduled tick is queued.
    _timer?.cancel();
    _timer = null;
    setState(() => _busy = true);
    _operation = _perform(work, automated: automated,
        remainderSeconds: remainderSeconds);
  }

  Future<void> _perform(Future<String> Function(TxTradingService) work,
      {required bool automated, int? remainderSeconds}) async {
    try {
      final trader = _trader!;
      final before = trader.current;
      final notice = await work(trader);
      final after = trader.current;
      // This operation uses only the previous and current verified states;
      // no readHistory(160) for each game minute.
      if (before.revision != after.revision) {
        _candles!.addCommit(before, after);
      }
      if (remainderSeconds != null) {
        // Only display a complete simulated minute after its commit succeeds.
        _fractionalSeconds = remainderSeconds;
      }
      if (automated) {
        _autoCount++;
        if (_autoCount >= 60) {
          _pause();
          if (mounted) setState(() =>
              _notice = '$notice · 已运行 60 分钟，自动暂停以保护存储');
          return;
        }
      }
      if (mounted) setState(() => _notice = notice);
    } catch (e) {
      // Whether the DB commit was ambiguous or a chart invariant failed,
      // stop instead of risking another order against stale state.
      _pause();
      if (mounted) setState(() =>
          _fault = '交易或历史检查异常；已暂停并保留数据：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_auto && _fault == null) _scheduleNext();
      }
    }
  }

  void _tick({bool automatic = false, int? remainderSeconds}) => _operate((service) async {
    final next = await service.nextTick();
    return '模拟第 ${TxSimulationClock.gameDay(next.session.step)} 天 '
        '${TxSimulationClock.hhmm(next.session.step)} · '
        'SQLite r${next.revision}';
  }, automated: automatic, remainderSeconds: remainderSeconds);

  int? _cents(String raw) {
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(raw.trim())) return null;
    final p = raw.trim().split('.');
    final integer = int.tryParse(p.first);
    final fractional = p.length == 1 ? 0 : int.tryParse(p[1].padRight(2, '0'));
    if (integer == null || fractional == null) return null;
    final price = integer * 100 + fractional;
    return price >= 1 && price <= TxEngine.maxPriceCents ? price : null;
  }

  void _trade(TxSide side) {
    final n = int.tryParse(_qty.text.trim());
    final limitPrice = _limit ? _cents(_price.text) : null;
    if (n == null || n <= 0 || n > TxEngine.maxQuantity ||
        (_limit && limitPrice == null)) {
      setState(() => _notice = '请输入有效股数和限价（最多两位小数）');
      return;
    }
    _operate((service) async {
      final order = await service.place(
        symbol: _symbolName, side: side,
        kind: _limit ? TxKind.limit : TxKind.market,
        quantity: n, limitPriceCents: limitPrice);
      return '${order.id} · 成交${order.filled}股，余量${order.remaining}股'
          ' · ${order.status.name}';
    });
  }

  void _cancel(String id) => _operate((service) async {
    await service.cancel(id);
    return '$id 已撤销，冻结已释放';
  });

  Widget _title(String t, {String? sub}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (sub != null) Text(sub,
          style: const TextStyle(fontSize: 12, color: Colors.white60)),
    ]),
  );

  Widget _metric(String label, String value) => SizedBox(
    width: 145,
    child: Padding(padding: const EdgeInsets.all(7), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 17,
            fontWeight: FontWeight.w600)),
      ],
    )),
  );

  Widget _chooseSymbol(TxSession session) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('SIM-A01')),
        ButtonSegment(value: 1, label: Text('SIM-A02')),
      ],
      selected: {_symbol},
      onSelectionChanged: (values) => setState(() {
        _symbol = values.first;
        _price.text = money(session.lastPrice(_symbolName));
      }),
    ),
  );

  Widget _depth(TxSession session) {
    final asks = session.engine.depth(_symbolName, TxSide.sell);
    final bids = session.engine.depth(_symbolName, TxSide.buy);
    final quantities = [...asks.map((e) => e.quantity),
      ...bids.map((e) => e.quantity), 1];
    final maxQty = quantities.reduce((a,b) => a > b ? a : b);
    Widget level(String label, int cents, int quantity, Color tint) => InkWell(
      onTap: () => setState(() {
        _limit = true;
        _price.text = money(cents);
        _page = 1;
      }),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
        child: Stack(children: [
          FractionallySizedBox(widthFactor: quantity / maxQty,
              child: Container(height: 22, color: tint.withAlpha(35))),
          Row(children: [
            SizedBox(width: 50, child: Text(label,
                style: TextStyle(fontSize: 12, color: tint))),
            Expanded(child: Text('¥${money(cents)}')),
            Text('$quantity 股'),
          ]),
        ])),
    );
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('真实五档盘口', style: TextStyle(fontWeight: FontWeight.bold)),
        for (var i = asks.length - 1; i >= 0; i--)
          level('卖${i+1}', asks[i].priceCents, asks[i].quantity, red),
        const Divider(),
        for (var i = 0; i < bids.length; i++)
          level('买${i+1}', bids[i].priceCents, bids[i].quantity, green),
        const Text('点价格可填入限价单',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
      ])),
    );
  }

  String _regimeName(int step, int symbolIndex) {
    final minute = step < 1 ? 1 : step;
    return switch (TxSession.marketRegime(minute, symbolIndex)) {
      0 => '上行趋势',
      1 => '区间震荡',
      2 => '下行趋势',
      _ => '高波动',
    };
  }

  Widget _market(TxSession session) {
    final minuteFills = session.currentMinuteFills
        .where((f) => f.symbol == _symbolName).toList();
    final minuteVolume = minuteFills.fold<int>(0, (sum, f) => sum + f.quantity);
    final price = session.lastPrice(_symbolName);
    final candles = _candles!.forSymbol(_symbolName);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _chooseSymbol(session),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_symbolName, style: const TextStyle(color: Colors.white70)),
          Text('¥${money(price)}', style: const TextStyle(
              fontSize: 34, fontWeight: FontWeight.bold)),
          Text('模拟日 ${TxRealtimeClock.gameDay(session.step, _fractionalSeconds)} '
              '${TxRealtimeClock.hhmmss(session.step, _fractionalSeconds)}'
              ' · 1×=现实1秒/游戏1秒'),
        ],
      ))),
      Card(child: Padding(padding: const EdgeInsets.all(12),
          child: TxCandleChart(candles: candles))),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('模拟市场参与者', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('2 个有限库存做市商 + 4 个独立资金账户的模拟交易者；'
              '它们会主动交易和提供流动性，玩家不操作也可能有成交。',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text('当前市场环境：${_regimeName(session.step, _symbol)}'),
          Text('本游戏分钟：${minuteFills.length} 笔真实撮合 · '
              '$minuteVolume 股成交量'),
          const Text('所有成交均在真实订单簿按价格与时间撮合；'
              '不模拟外部证券、不保证每一分钟都有成交。',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ))),
      _depth(session),
      _title('游戏时间与行情速度', sub: '24 小时制，前台运行；失败或切后台立即暂停'),
      Card(child: Padding(padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: _ready ? _toggle : null,
              icon: Icon(_auto ? Icons.pause : Icons.play_arrow),
              label: Text(_auto ? '暂停' : '运行'),
            )),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _ready ? () => _tick() : null,
                child: const Text('+1 分钟')),
            const SizedBox(width: 8),
            DropdownButton<int>(value: _speed,
              items: TxRealtimeClock.speeds.map((value) =>
                  DropdownMenuItem(value: value, child: Text('$value×'))).toList(),
              onChanged: (v) {
              if (v == null) return;
              setState(() => _speed = v);
              if (_auto && _ready) _scheduleNext();
            }),
          ]),
          const Text('1×/2×/5×/10×/15×/30×/60×：每现实秒推进对应游戏秒数。'
              '每游戏分钟提交一次 SQLite；存档慢时自动降速，不补跳。',
              style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 4),
          Text('每次连续运行最多 60 游戏分钟，自动暂停防止数据库过快增长。',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      )),
      const SizedBox(height: 8),
      const Text('K 线的开高低收取自已提交的参考价格及真实撮合记录；'
          '成交量不包含挂单，只统计实际成交的股份。',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]);
  }

  Widget _trading(TxSession session) {
    final account = session.engine.account(TxSession.playerId);
    final ask = session.engine.depth(_symbolName, TxSide.sell);
    final bid = session.engine.depth(_symbolName, TxSide.buy);
    final active = session.playerOrders.where((o) =>
      o.status == TxStatus.open || o.status == TxStatus.partiallyFilled).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      _title('交易委托', sub: '市价可能跨档滑点；真实资金/库存限制'),
      _chooseSymbol(session),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Wrap(children: [
          _metric('可用资金', '¥${money(account.availableCashCents)}'),
          _metric('可卖数量', '${account.availableSharesOf(_symbolName)} 股'),
          _metric('卖一', ask.isEmpty ? '—' : '¥${money(ask.first.priceCents)}'),
          _metric('买一', bid.isEmpty ? '—' : '¥${money(bid.first.priceCents)}'),
        ]),
        SwitchListTile(title: Text(_limit ? '限价委托' : '市价委托'),
          value: _limit, onChanged: _ready ? (v) => setState(() => _limit=v) : null),
        TextField(controller: _qty, enabled: _ready,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '委托股数',
              border: OutlineInputBorder())),
        if (_limit) ...[
          const SizedBox(height: 10),
          TextField(controller: _price, enabled: _ready,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '限价 ¥',
                border: OutlineInputBorder())),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: _ready ? () => _trade(TxSide.buy) : null,
            style: FilledButton.styleFrom(backgroundColor: green,
                foregroundColor: Colors.black), child: const Text('买入'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(
            onPressed: _ready ? () => _trade(TxSide.sell) : null,
            style: FilledButton.styleFrom(backgroundColor: red,
                foregroundColor: Colors.black), child: const Text('卖出'))),
        ]),
      ]))),
      _title('活动委托', sub: '撤单后释放冻结资金或持仓'),
      if (active.isEmpty) const ListTile(title: Text('暂无活动委托')),
      for (final order in active)
        Card(child: ListTile(
          title: Text('${order.symbol} · ${order.side==TxSide.buy?'买':'卖'} '
              '${order.remaining}/${order.quantity}股'),
          subtitle: Text('${order.id} · ¥${money(order.limitPriceCents!)}'),
          trailing: IconButton(tooltip: '撤单',
            icon: const Icon(Icons.close),
            onPressed: _ready ? () => _cancel(order.id) : null),
        )),
    ]);
  }

  Widget _assets(TxSession session, TxStoredSession saved) {
    final account = session.engine.account(TxSession.playerId);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _title('资金与资产', sub: '总资产按最新参考/成交价标记，并非保证可清算价值'),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(children: [
        _metric('总资产估值', '¥${money(session.totalAssetsCents)}'),
        _metric('现金余额', '¥${money(account.cashCents)}'),
        _metric('可用现金', '¥${money(account.availableCashCents)}'),
        _metric('冻结资金', '¥${money(account.reservedCashCents)}'),
      ]))),
      _title('持仓'),
      for (final symbol in TxSession.symbols)
        Card(child: ListTile(title: Text(symbol),
          subtitle: Text('持有 ${account.sharesOf(symbol)} · '
              '冻结 ${account.reservedSharesOf(symbol)} · '
              '可卖 ${account.availableSharesOf(symbol)}'),
          trailing: Text('¥${money(account.sharesOf(symbol) * session.lastPrice(symbol))}'))),
      _title('存档状态'),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('修订 ${saved.revision} · 模拟步数 ${session.step}'),
          Text('第 ${TxRealtimeClock.gameDay(session.step, _fractionalSeconds)} 天 '
              '${TxRealtimeClock.hhmmss(session.step, _fractionalSeconds)}'),
          Text('校验 ${saved.sha256.substring(0,16)}…'),
        ],
      ))),
    ]);
  }

  String _participantLabel(String accountId) {
    if (accountId == TxSession.playerId) return '玩家';
    if (accountId.startsWith('LP_')) return '做市商 $accountId';
    if (accountId.startsWith('NPC_')) return '模拟交易者 ${accountId.substring(4)}';
    return accountId;
  }

  Widget _records(TxSession session) {
    final orders = session.playerOrders.take(100).toList();
    final playerFills = session.playerFills.take(100).toList();
    final tape = session.engine.fills.reversed.take(100).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      _title('真实成交与交易记录', sub: '我的成交与市场逐笔分开显示；最多展示最近 100 条'),
      SegmentedButton<int>(segments: const [
        ButtonSegment(value: 0, label: Text('我的委托')),
        ButtonSegment(value: 1, label: Text('我的成交')),
        ButtonSegment(value: 2, label: Text('市场逐笔')),
      ], selected: {_recordMode},
        onSelectionChanged: (v) => setState(() => _recordMode = v.first)),
      if (_recordMode == 0 && orders.isEmpty)
        const ListTile(title: Text('暂无个人委托')),
      if (_recordMode == 1 && playerFills.isEmpty)
        const ListTile(title: Text('暂无个人成交')),
      if (_recordMode == 2 && tape.isEmpty)
        const ListTile(title: Text('市场尚无实际成交')),
      if (_recordMode == 0) for (final order in orders)
        Card(child: ListTile(dense: true,
          title: Text('${order.id} ${order.symbol} '
              '${order.side == TxSide.buy ? '买' : '卖'}'),
          subtitle: Text('${order.status.name} · '
              '成交${order.filled} · 余${order.remaining}'),
          trailing: Text(order.limitPriceCents == null ? '市价' :
              '¥${money(order.limitPriceCents!)}'))),
      if (_recordMode == 1) for (final f in playerFills)
        Card(child: ListTile(dense: true,
          title: Text('${f.id} ${f.symbol} ${f.quantity}股'),
          subtitle: Text(session.engine.order(f.buyOrderId).ownerId ==
              TxSession.playerId ? '玩家买入' : '玩家卖出'),
          trailing: Text('¥${money(f.priceCents)}'))),
      if (_recordMode == 2) for (final f in tape)
        Card(child: ListTile(dense: true,
          title: Text('${f.id} ${f.symbol} ${f.quantity}股'),
          subtitle: Text('${_participantLabel(session.engine.order(f.buyOrderId).ownerId)} 买'
              ' ← ${_participantLabel(session.engine.order(f.sellOrderId).ownerId)} 卖'),
          trailing: Text('¥${money(f.priceCents)}'))),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _qty.dispose();
    _price.dispose();
    final work = _operation;
    if (work == null) {
      _trader?.close();
    } else {
      work.whenComplete(() async => _trader?.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(
        child: CircularProgressIndicator()));
    if (_trader == null) return Scaffold(appBar: AppBar(
      title: const Text('Terminal X · 存档保护')),
      body: Padding(padding: const EdgeInsets.all(18),
        child: SelectableText(_fault ?? '存档读取失败')));

    final stored = _trader!.current;
    final session = stored.session;
    final day = TxRealtimeClock.gameDay(session.step, _fractionalSeconds);
    final hhmm = TxRealtimeClock.hhmmss(session.step, _fractionalSeconds);
    return Scaffold(
      appBar: AppBar(title: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TERMINAL X', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('版本 $appVersion · 离线模拟交易', style: const TextStyle(fontSize: 11)),
        ]), actions: [
          IconButton(tooltip: _auto ? '暂停' : '运行',
              onPressed: _ready ? _toggle : null,
              icon: Icon(_auto ? Icons.pause_circle : Icons.play_circle_outline)),
        ]),
      body: Column(children: [
        Container(width: double.infinity, color: const Color(0xFF111B2A),
          padding: const EdgeInsets.all(10),
          child: Text('模拟第 $day 天 $hhmm · 第${session.step}分钟 '
              '· ${_auto ? '运行 ${_speed}×' : '暂停'} · SQLite r${stored.revision}',
              style: const TextStyle(color: Colors.white70, fontSize: 12))),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_fault != null) Padding(padding: const EdgeInsets.all(10),
            child: SelectableText(_fault!, style: const TextStyle(color: red))),
        if (_fault == null) Padding(padding: const EdgeInsets.all(8),
          child: Text(_notice, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12))),
        Expanded(child: switch (_page) {
          0 => _market(session),
          1 => _trading(session),
          2 => _assets(session, stored),
          _ => _records(session),
        }),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: _page,
        onDestinationSelected: (i) => setState(() => _page=i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.candlestick_chart), label: '行情'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: '交易'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: '资产'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: '记录'),
        ]),
    );
  }
}
