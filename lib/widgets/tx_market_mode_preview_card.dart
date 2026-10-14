import 'package:flutter/material.dart';

import '../market/tx_market_profiles.dart';
import 'tx_terminal_theme.dart';

/// Fallback detail card for an independent market mode. The normal terminal
/// opens the executable independent panel; compact embedders may still use
/// this profile-only card.
class TxMarketModePreviewCard extends StatelessWidget {
  const TxMarketModePreviewCard({
    super.key,
    required this.profile,
    this.onReturnToConnected,
  });

  final TxMarketProfile profile;
  final VoidCallback? onReturnToConnected;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.construction_outlined,
                      size: 20, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${profile.label} · 独立核心',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  const Text('已连接',
                      style: TextStyle(
                          fontSize: 11, color: TxTerminalColors.buy)),
                ],
              ),
              const SizedBox(height: 8),
              Text('${profile.category} · 计价 ${profile.quoteCurrency} · '
                  '单位 ${profile.orderUnit}',
                  style: const TextStyle(
                      fontSize: 11, color: TxTerminalColors.secondaryText)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _chip(profile.session),
                _chip(profile.settlement),
                _chip('最小变动 ${profile.tickSize}'),
                _chip('杠杆 ${profile.maxLeverage}'),
                _chip(profile.supportsShort ? '支持做空规则' : '仅做多规则'),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: profile.independentCoreProgress,
                    minHeight: 6,
                    color: TxTerminalColors.buy,
                    backgroundColor: Color(0xFF2A3445)),
              ),
              const SizedBox(height: 6),
              Text('独立账户/风控/撮合核心 ${(profile.independentCoreProgress * 100).round()}% · '
                  'SQLite CAS · 真实盘口 · 交易记录',
                  style: const TextStyle(fontSize: 10, color: TxTerminalColors.buy)),
              const SizedBox(height: 4),
              const Text('已具备独立的仓位方向、加权持仓成本、保证金占用、'
                  '未实现盈亏、强平预警、A 股 T+1 可卖数量模型、Dart 价时撮合、'
                  'Maker/Taker 费率、统一行情标记、跨账户原子日结、严格运行时快照、'
                  'SQLite 独立 CAS 快照、真实盘口滑点预览、盘口不足时的真实强平报告；'
                  '非 A 股模式使用独立 Dart 执行核心，与 Rust A 股账本隔离。',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              const Text('本模式拥有独立现金、持仓、K 线、盘口和成交记录，'
                  '不会复用 A 股现货账本。',
                  style: TextStyle(fontSize: 10, color: Colors.white54)),
              const SizedBox(height: 10),
              const Text('已登记模拟标的', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: TxTerminalColors.cyan)),
              const SizedBox(height: 4),
              for (final instrument in profile.instruments)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${instrument.symbol} · ${instrument.name}',
                          style: const TextStyle(fontSize: 11,
                              color: Colors.white70)),
                      Text('${instrument.kind} · ${instrument.orderUnit} · '
                          '${instrument.tickSize} · ${instrument.contractMultiplier}',
                          style: const TextStyle(fontSize: 10,
                              color: TxTerminalColors.secondaryText)),
                    ])),
                    const SizedBox(width: 6),
                    Text(instrument.connectionLabel,
                        style: const TextStyle(fontSize: 10,
                            color: TxTerminalColors.buy)),
                  ]),
                ),
              if (onReturnToConnected != null) ...[
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: onReturnToConnected,
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: const Text('回到 A 股现货核心'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amberAccent.withAlpha(16),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.amberAccent.withAlpha(90)),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
      );
}
