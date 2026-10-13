import 'package:flutter/material.dart';

import '../engine/tx_engine.dart';
import 'tx_terminal_theme.dart';

/// A persistent, thumb-reachable REVIEW affordance, not a trade execution.
/// The parent must still show its existing revision-locked confirm dialog.
class TxTicketSubmitBar extends StatelessWidget {
  const TxTicketSubmitBar({super.key, required this.side,
      required this.isLimit, this.timeInForce = TxTimeInForce.gtc,
      required this.enabled, required this.onReview});

  final TxSide side;
  final bool isLimit;
  final TxTimeInForce timeInForce;
  final bool enabled;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final buying = side == TxSide.buy;
    return SafeArea(top: false, child: DecoratedBox(
      decoration: const BoxDecoration(
        color: TxTerminalColors.surface,
        border: Border(top: BorderSide(color: TxTerminalColors.border)),
      ),
      child: Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.shield_outlined, size: 14, color: Colors.white60),
            const SizedBox(width: 5),
            const Expanded(child: Text('模拟交易 · 点击后仍需核对确认',
              style: TextStyle(fontSize: 11, color: Colors.white60))),
            Text(isLimit ? '限价' : '市价',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
            if (isLimit)
              Text(' · ${timeInForce.label}',
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, height: 48,
            child: FilledButton.icon(
              onPressed: enabled ? onReview : null,
              style: FilledButton.styleFrom(
                backgroundColor: buying
                    ? TxTerminalColors.buy : TxTerminalColors.sell,
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0xFF314152),
                disabledForegroundColor: Colors.white54),
              icon: const Icon(Icons.fact_check_outlined, size: 19),
              label: Text('检查并${buying ? '买入' : '卖出'}'),
            )),
        ]),
      ),
    ));
  }
}
