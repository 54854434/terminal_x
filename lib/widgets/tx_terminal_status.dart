import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../market/tx_realtime_clock.dart';
import 'tx_terminal_theme.dart';

/// Display-only status strip: ticks never rebuild page navigation or tabs.
class TxTerminalStatus extends StatelessWidget {
  const TxTerminalStatus({super.key, required this.seconds,
    required this.step, required this.revision,
    required this.running, required this.speed, required this.busy,
    this.settling, this.settlementPhase,
    this.pendingSave = false, this.pendingOperations = 0,
    this.pendingGameMinutes = 0, this.automaticSaveMinutes = 1});

  final ValueListenable<double> seconds;
  final int step;
  final int revision;
  final bool running;
  final int speed;
  final bool busy;
  /// A notifier keeps the small status strip responsive while the parent
  /// deliberately avoids rebuilding the whole trading screen for a pending
  /// automatic commit.
  final ValueListenable<bool>? settling;
  final ValueListenable<double>? settlementPhase;
  final bool pendingSave;
  final int pendingOperations;
  final int pendingGameMinutes;
  final int automaticSaveMinutes;

  @override
  Widget build(BuildContext context) {
    final notifier = settling;
    if (notifier == null) return _body(context, false);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, child) => _body(context, value));
  }

  Widget _body(BuildContext context, bool isSettling) {
    final saveMinutes = automaticSaveMinutes < 1 ? 1 : automaticSaveMinutes;
    return DecoratedBox(
    decoration: const BoxDecoration(
      color: TxTerminalColors.surface,
      border: Border(bottom: BorderSide(color: TxTerminalColors.border))),
    child: Padding(padding: const EdgeInsets.symmetric(
      horizontal: 12, vertical: 9), child: Row(children: [
      DecoratedBox(decoration: BoxDecoration(
        color: running ? TxTerminalColors.buy.withAlpha(25) : TxTerminalColors.raised,
        borderRadius: BorderRadius.circular(9)),
        child: Padding(padding: const EdgeInsets.symmetric(
          horizontal: 9, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(running ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 16, color: running ? TxTerminalColors.buy :
                TxTerminalColors.secondaryText),
            const SizedBox(width: 3),
            Text(running ? '$speed×' : '暂停',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: running ? TxTerminalColors.buy :
                  TxTerminalColors.secondaryText)),
          ]))),
      const SizedBox(width: 10),
      Expanded(child: ValueListenableBuilder<double>(
        valueListenable: seconds,
        builder: (context, value, child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('第 ${TxRealtimeClock.gameDay(step, value.floor())} 天  '
              '${TxRealtimeClock.hhmmss(step, value.floor())}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600)),
            Text('游戏分钟 $step  ·  SQLite r$revision',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
            if (pendingSave)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('待保存 $pendingOperations 项 · 每 $saveMinutes 个游戏分钟自动保存',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10,
                    color: TxTerminalColors.primary)),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: (pendingGameMinutes / saveMinutes)
                      .clamp(0.0, 1.0).toDouble(),
                  minHeight: 3,
                  backgroundColor: TxTerminalColors.raised,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      TxTerminalColors.primary)),
              ]),
            if (isSettling)
              const Text('正在处理当前结算，未确认时间不会前进',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10,
                  color: TxTerminalColors.primary)),
          ]))),
      if (busy || isSettling) Padding(
        padding: const EdgeInsets.only(left: 6),
        child: _syncIcon(isSettling)),
    ])),
  );
  }

  Widget _syncIcon(bool isSettling) {
    final phase = settlementPhase;
    if (!isSettling || phase == null) {
      return const Icon(Icons.sync, size: 16, color: TxTerminalColors.primary);
    }
    return ValueListenableBuilder<double>(
      valueListenable: phase,
      builder: (context, value, child) => Transform.rotate(
        angle: value * 6.283185307179586,
        child: const Icon(Icons.sync, size: 16,
          color: TxTerminalColors.primary)));
  }
}
