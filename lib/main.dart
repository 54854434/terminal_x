import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TerminalX());

class TerminalX extends StatelessWidget {
  const TerminalX({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Terminal X',
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
  final _random = Random();
  final _qty = TextEditingController(text: '100');
  final _limit = TextEditingController(text: '10.00');
  final symbols = ['SIM-A01', 'SIM-A02'];
  final prices = [10.00, 25.00];
  final owned = [0, 0];
  final pending = <Map<String, dynamic>>[];
  final trades = <String>[];
  double cash = 1000000;
  int selected = 0;
  int step = 0;
  bool limitOrder = false;
  String message = '本地离线演示：点击「推进行情」更新虚拟报价。';

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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('terminal_state');
    if (raw == null) return;
    try {
      final state = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        cash = (state['cash'] as num).toDouble();
        for (var i = 0; i < 2; i++) {
          prices[i] = (state['prices'][i] as num).toDouble();
          owned[i] = (state['owned'][i] as num).toInt();
        }
        step = (state['step'] as num).toInt();
        pending.addAll((state['pending'] as List).map((e) => Map<String, dynamic>.from(e)));
        trades.addAll((state['trades'] as List).cast<String>());
      });
    } catch (_) {
      setState(() => message = '存档格式错误，已使用默认账户。');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terminal_state', jsonEncode({
      'cash': cash, 'prices': prices, 'owned': owned,
      'pending': pending, 'trades': trades, 'step': step,
    }));
  }

  // Five synthetic ask/bid levels; all quantities are executable in this demo.
  List<Map<String, num>> levels(int symbol, {required bool asks}) {
    final mid = prices[symbol];
    return List.generate(5, (i) => {
      'price': double.parse((mid + (asks ? 1 : -1) * (i + 1) * 0.01).toStringAsFixed(2)),
      'qty': 100 + (i * 150),
    });
  }

  String _money(num n) => n.toStringAsFixed(2);

  void _trade({required int symbol, required bool buy, required int quantity,
      required bool market, double? priceLimit}) {
    if (quantity <= 0) {setState(() => message = '数量必须大于0'); return;}
    var remaining = quantity;
    var executed = 0;
    var total = 0.0;
    final book = levels(symbol, asks: buy);
    for (final entry in book) {
      final price = (entry['price'] as num).toDouble();
      if (!market && ((buy && price > priceLimit!) || (!buy && price < priceLimit!))) break;
      final available = (entry['qty'] as num).toInt();
      final q = min(remaining, available);
      if (buy && cash + 1e-8 < price * q) {
        final affordable = (cash / price).floor();
        if (affordable <= 0) break;
        final actual = min(q, affordable);
        cash -= actual * price;
        owned[symbol] += actual;
        total += actual * price;
        executed += actual;
        remaining -= actual;
        break;
      }
      if (!buy && owned[symbol] < q) {
        final actual = min(q, owned[symbol]);
        if (actual <= 0) break;
        cash += actual * price;
        owned[symbol] -= actual;
        total += actual * price;
        executed += actual;
        remaining -= actual;
        break;
      }
      if (buy) {cash -= price * q; owned[symbol] += q;}
      else {cash += price * q; owned[symbol] -= q;}
      total += price * q;
      executed += q;
      remaining -= q;
      if (remaining == 0) break;
    }
    setState(() {
      if (executed > 0) {
        trades.insert(0, '${buy ? '买入' : '卖出'} ${symbols[symbol]} $executed 股 均价 ${_money(total / executed)}');
        if (trades.length > 20) trades.removeLast();
      }
      if (!market && remaining > 0) {
        pending.add({'symbol': symbol, 'buy': buy, 'qty': remaining, 'limit': priceLimit});
      }
      message = '成交 $executed 股；${market ? '未成交数量取消' : '剩余已挂单'} $remaining 股。';
    });
    _save();
  }

  void _submit(bool buy) {
    final quantity = int.tryParse(_qty.text.trim());
    final requestedPrice = double.tryParse(_limit.text.trim());
    if (quantity == null || quantity <= 0 || (limitOrder && (requestedPrice == null || requestedPrice <= 0))) {
      setState(() => message = '请输入有效的数量和价格。');
      return;
    }
    _trade(symbol: selected, buy: buy, quantity: quantity, market: !limitOrder,
      priceLimit: requestedPrice);
  }

  void _nextTick() {
    setState(() {
      for (var i = 0; i < 2; i++) {
        final move = (_random.nextInt(7) - 3) * 0.01;
        prices[i] = max(0.10, double.parse((prices[i] + move).toStringAsFixed(2)));
      }
      step++;
      message = '行情推进到第 $step 步（演示随机报价）。';
    });
    // Process eligible pending limit orders on each tick.
    final due = List<Map<String, dynamic>>.from(pending);
    pending.clear();
    for (final order in due) {
      _trade(symbol: order['symbol'] as int, buy: order['buy'] as bool,
        quantity: order['qty'] as int, market: false,
        priceLimit: (order['limit'] as num).toDouble());
    }
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final market = prices[selected];
    final assets = cash + List.generate(2, (i) => owned[i] * prices[i]).reduce((a, b) => a + b);
    final asks = levels(selected, asks: true).reversed.toList();
    final bids = levels(selected, asks: false);
    return Scaffold(
      appBar: AppBar(title: const Text('TERMINAL X · 本地模拟'),
        actions: [IconButton(icon: const Icon(Icons.skip_next), tooltip: '推进行情', onPressed: _nextTick)]),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Text('总资产 ¥${_money(assets)}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        Text('现金 ¥${_money(cash)}  ·  第 $step 步', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 14),
        SegmentedButton<int>(segments: const [
          ButtonSegment(value: 0, label: Text('SIM-A01')),
          ButtonSegment(value: 1, label: Text('SIM-A02')),
        ], selected: {selected}, onSelectionChanged: (s) => setState(() {
          selected = s.first;
          _limit.text = prices[selected].toStringAsFixed(2);
        })),
        const SizedBox(height: 16),
        Text('¥${_money(market)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        Text('持仓：${owned[selected]} 股', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        const Text('五档合成盘口（演示）', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final l in asks) Text('卖盘   ¥${_money(l['price']!)}            ${l['qty']} 股',
          style: const TextStyle(color: Color(0xFFFA7676))),
        const Divider(),
        for (final l in bids) Text('买盘   ¥${_money(l['price']!)}            ${l['qty']} 股',
          style: const TextStyle(color: Color(0xFF54D49B))),
        const SizedBox(height: 12),
        Row(children: [
          const Text('限价单'),
          Switch(value: limitOrder, onChanged: (v) => setState(() => limitOrder = v)),
          Expanded(child: TextField(controller: _qty, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '数量（股）'))),
        ]),
        if (limitOrder) TextField(controller: _limit, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '限价')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton(onPressed: () => _submit(true), child: const Text('买入'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => _submit(false), child: const Text('卖出'))),
        ]),
        OutlinedButton.icon(onPressed: _nextTick, icon: const Icon(Icons.fast_forward), label: const Text('推进行情一步')),
        Text(message, style: const TextStyle(color: Colors.amberAccent)),
        const SizedBox(height: 14),
        Text('挂单（${pending.length}）', style: const TextStyle(fontWeight: FontWeight.bold)),
        for (var i = 0; i < pending.length; i++)
          ListTile(dense: true, title: Text('${pending[i]['buy'] ? '买' : '卖'} ${symbols[pending[i]['symbol'] as int]} ${pending[i]['qty']}股 @ ${pending[i]['limit']}'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () {
              setState(() => pending.removeAt(i)); _save();
            })),
        const SizedBox(height: 12),
        const Text('最近成交', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final trade in trades.take(8)) Text(trade),
        const SizedBox(height: 40),
        const Text('仅供本地功能验证。尚未实现K线、完整订单簿、资金冻结、市场规则或AI策略。',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
