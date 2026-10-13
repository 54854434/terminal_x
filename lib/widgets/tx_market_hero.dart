import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../market/tx_realtime_clock.dart';
import 'tx_terminal_theme.dart';

/// Only the indicative quote and simulated clock rebuild on a vsync tick.
/// This never writes an order, storage revision or committed candle.
class TxMarketHero extends StatelessWidget {
  const TxMarketHero({super.key, required this.symbol,
    required this.committedPriceCents, required this.step,
    required this.seconds, required this.indicativeCents,
    required this.onBuy, required this.onSell, this.pending = false});

  final String symbol;
  final int committedPriceCents;
  final int step;
  final ValueListenable<double> seconds;
  final double Function(double seconds) indicativeCents;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final bool pending;

  String _yuan(int cents) => (cents / 100).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.show_chart, color: TxTerminalColors.cyan, size: 18),
        const SizedBox(width: 7),
        Expanded(child: Text(symbol, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700))),
        Container(padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: TxTerminalColors.raised,
            borderRadius: BorderRadius.circular(8)),
          child: const Text('OFFLINE · SIM',
            style: TextStyle(fontSize: 10,
              color: TxTerminalColors.secondaryText))),
      ]),
      const SizedBox(height: 11),
      ValueListenableBuilder<double>(
        valueListenable: seconds,
        builder: (context, value, child) {
          final quote = indicativeCents(value);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(label: '模拟指示价 ¥${(quote / 100).toStringAsFixed(4)}，不可用于真实成交',
              child: Text('¥${(quote / 100).toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 32,
                  color: TxTerminalColors.cyan, fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()]))),
            const SizedBox(height: 3),
            Text('游戏第 ${TxRealtimeClock.gameDay(step, value.floor())} 天 · '
              '${TxRealtimeClock.hhmmss(step, value.floor())}',
              style: const TextStyle(fontSize: 12,
                color: TxTerminalColors.secondaryText)),
          ]);
        }),
      const SizedBox(height: 6),
      Text(pending
          ? '当前盘口为待保存候选 · SQLite 恢复收盘 ¥${_yuan(committedPriceCents)}'
          : '指示走势逐帧演示 · 非真实成交 | 已提交收盘 ¥${_yuan(committedPriceCents)}',
        style: const TextStyle(
          color: TxTerminalColors.secondaryText, fontSize: 11)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: onBuy, icon: const Icon(Icons.add_circle_outline, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: TxTerminalColors.buy),
          label: const Text('快捷买入'))),
        const SizedBox(width: 9),
        Expanded(child: OutlinedButton.icon(
          onPressed: onSell, icon: const Icon(Icons.remove_circle_outline, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: TxTerminalColors.sell),
          label: const Text('快捷卖出'))),
      ]),
    ]),
  ));
}
