import 'package:flutter/material.dart';

import '../engine/tx_session.dart';
import '../market/tx_market_objectives.dart';
import 'tx_terminal_theme.dart';

/// Compact, read-only strategy layer. Every progress number is derived from
/// actual fills, resting depth or the player's current account.
class TxMarketObjectivesCard extends StatefulWidget {
  const TxMarketObjectivesCard({
    super.key,
    required this.session,
    required this.symbol,
  });

  final TxSession session;
  final String symbol;

  @override
  State<TxMarketObjectivesCard> createState() =>
      _TxMarketObjectivesCardState();
}

class _TxMarketObjectivesCardState extends State<TxMarketObjectivesCard> {
  String? _answeredPromptId;
  int? _selectedAnswer;

  String _money(int cents) => '¥${(cents / 100).toStringAsFixed(2)}';

  @override
  void didUpdateWidget(covariant TxMarketObjectivesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol ||
        oldWidget.session.step != widget.session.step ||
        oldWidget.session.marketSessionStatus.state !=
            widget.session.marketSessionStatus.state) {
      _answeredPromptId = null;
      _selectedAnswer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final symbol = widget.symbol;
    final objectives = TxMarketObjectives.evaluate(session, symbol);
    final briefing = TxMarketObjectives.briefing(session, symbol);
    final research = TxMarketObjectives.researchPrompt(session, symbol);
    final completed = objectives.where((item) => item.complete).length;
    final spread = briefing.spreadCents == null
        ? '—' : _money(briefing.spreadCents!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.flag_outlined,
                  size: 18, color: TxTerminalColors.primary),
              const SizedBox(width: 7),
              const Expanded(child: Text('本局策略任务',
                  style: TextStyle(fontWeight: FontWeight.w700))),
              Text('$completed/${objectives.length} 已完成',
                  style: const TextStyle(
                      color: TxTerminalColors.secondaryText, fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Text('第 ${session.step < 1 ? 1 : session.step} 分钟 · 目标来自真实状态，不自动下单',
                style: const TextStyle(
                    color: TxTerminalColors.secondaryText, fontSize: 11)),
            const SizedBox(height: 8),
            if (!session.marketSessionStatus.isOpen)
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: TxTerminalColors.raised,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: TxTerminalColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.nightlight_outlined, size: 18,
                      color: TxTerminalColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('盘后研究 · ${session.marketSessionStatus.label}',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Text(
                        session.marketSessionStatus.minutesToTransition == null
                            ? '下一交易时段尚未确定'
                            : '距下一状态切换约 ${session.marketSessionStatus.minutesToTransition} 个游戏分钟；'
                                '期间不生成成交或临时 K 线波动',
                        style: const TextStyle(fontSize: 10,
                            color: TxTerminalColors.secondaryText),
                      ),
                    ],
                  )),
                ]),
              ),
            if (!session.marketSessionStatus.isOpen) ...[
              const SizedBox(height: 8),
              _researchChallenge(research),
            ],
            if (!session.marketSessionStatus.isOpen)
              const SizedBox(height: 8),
            for (final item in objectives) ...[
              Row(children: [
                Icon(item.complete ? Icons.check_circle : Icons.circle_outlined,
                    size: 16,
                    color: item.complete
                        ? TxTerminalColors.buy
                        : TxTerminalColors.secondaryText),
                const SizedBox(width: 7),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.title,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  Text(item.description,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10,
                          color: TxTerminalColors.secondaryText)),
                ])),
                Text('${item.progress}/${item.target}${item.unit}',
                    style: TextStyle(fontSize: 11,
                        color: item.complete
                            ? TxTerminalColors.buy
                            : Colors.white70)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: item.fraction, minHeight: 4),
              const SizedBox(height: 7),
            ],
            const Divider(height: 12),
            Row(children: [
              const Icon(Icons.insights_outlined,
                  size: 17, color: TxTerminalColors.cyan),
              const SizedBox(width: 6),
              Expanded(child: Text('市场解读 · ${briefing.regime}',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600))),
              Text('距阶段切换 ${briefing.nextPhaseInMinutes} 分钟',
                  style: const TextStyle(fontSize: 10,
                      color: TxTerminalColors.secondaryText)),
            ]),
            const SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 5, children: [
              _chip('价差 $spread', TxTerminalColors.secondaryText),
              _chip(briefing.liquidity, TxTerminalColors.cyan),
              _chip(briefing.pressure, TxTerminalColors.primary),
            ]),
            const SizedBox(height: 5),
            const Text('盘口压力只是当前可见挂单的快照，不是涨跌预测；成交量和任务进度只认真实撮合。',
                style: TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _researchChallenge(TxMarketResearchPrompt prompt) {
    final selected = _answeredPromptId == prompt.id ? _selectedAnswer : null;
    final answered = selected != null;
    final correct = selected == prompt.correctIndex;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: TxTerminalColors.raised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: TxTerminalColors.cyan.withAlpha(120)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.school_outlined, size: 18,
              color: TxTerminalColors.cyan),
          const SizedBox(width: 7),
          const Expanded(child: Text('盘后研究挑战',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          const Text('不影响账户',
              style: TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
        ]),
        const SizedBox(height: 5),
        Text(prompt.question,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
        const SizedBox(height: 6),
        for (var i = 0; i < prompt.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: answered
                    ? null
                    : () => setState(() {
                        _answeredPromptId = prompt.id;
                        _selectedAnswer = i;
                      }),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 7),
                ),
                child: Text('${i + 1}. ${prompt.options[i]}',
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
        if (answered) ...[
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(correct ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: correct ? TxTerminalColors.buy : Colors.amberAccent),
            const SizedBox(width: 6),
            Expanded(child: Text(
              '${correct ? '回答正确' : '先记下这个边界'} · ${prompt.explanation}',
              style: TextStyle(fontSize: 10,
                  color: correct ? TxTerminalColors.buy : Colors.amberAccent),
            )),
          ]),
          if (!correct)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _answeredPromptId = null;
                  _selectedAnswer = null;
                }),
                child: const Text('再试一次', style: TextStyle(fontSize: 10)),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(100)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );
}
