import 'package:flutter/material.dart';

import '../market/tx_market_ecosystem.dart';
import '../market/tx_market_book_impact.dart';
import '../market/tx_market_profiles.dart';
import '../engine/tx_session.dart';
import 'tx_terminal_theme.dart';
import 'tx_market_mode_preview_card.dart';

/// Dense market-structure panel: real participants, real visible depth and
/// real minute fills. It deliberately contains no quests, rewards or story.
class TxMarketEcosystemCard extends StatelessWidget {
  const TxMarketEcosystemCard({
    super.key,
    required this.session,
    required this.symbol,
    this.profile = TxMarketProfile.aShare,
  });

  final TxSession session;
  final String symbol;
  final TxMarketProfile profile;

  String _currencyMark() => switch (profile.quoteCurrency) {
    'CNY' => '¥',
    'USD' => '\$',
    'USDT' => '₮',
    _ => '${profile.quoteCurrency} ',
  };

  String _money(int cents) =>
      '${_currencyMark()}${(cents / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    if (!profile.isCoreConnected) {
      return TxMarketModePreviewCard(profile: profile);
    }
    final snapshot = TxMarketEcosystemSnapshot.evaluate(session, symbol);
    final spread = snapshot.spreadCents == null
        ? '—' : '${_currencyMark()}'
            '${(snapshot.spreadCents! / 100).toStringAsFixed(2)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hub_outlined,
                size: 19, color: TxTerminalColors.primary),
            const SizedBox(width: 7),
            Expanded(child: Text('${profile.label}市场生态 · 真实参与者',
                style: TextStyle(fontWeight: FontWeight.w700))),
            Text(snapshot.regime,
                style: const TextStyle(fontSize: 11,
                    color: TxTerminalColors.secondaryText)),
          ]),
          const SizedBox(height: 4),
          Text('${profile.category} · ${profile.quoteCurrency} · '
              '多空方向来自真实买卖与成交；当前版本不伪造卖空仓位',
              style: TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 9),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip('买盘 ${snapshot.bidShares} ${profile.orderUnit}',
                TxTerminalColors.buy),
            _chip('卖盘 ${snapshot.askShares} ${profile.orderUnit}',
                TxTerminalColors.sell),
            _chip('价差 $spread', TxTerminalColors.cyan),
            _chip('可见 ${snapshot.visibleOrders} 笔', Colors.white70),
          ]),
          const SizedBox(height: 10),
          const Text('资金影响观察', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: TxTerminalColors.cyan)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(
              '账户权益 ${_money(snapshot.playerEquityCents)} · '
              '可用现金 ${_money(snapshot.playerAvailableCashCents)}',
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText))),
            Text('${snapshot.capitalToBookRatio.toStringAsFixed(1)}×盘口',
                style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: snapshot.capitalToBookRatio >= 1
                        ? TxTerminalColors.primary
                        : TxTerminalColors.secondaryText)),
          ]),
          const SizedBox(height: 3),
          const Text('这是相对当前五档可见名义深度的仓位参考，不会自动改变价格；真实操盘影响必须通过订单成交产生。',
              style: TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 8),
          const Text('大额订单影响预览 · 只读扫描真实五档', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: TxTerminalColors.cyan)),
          const SizedBox(height: 4),
          _impactRow('玩家买入可吃卖盘', snapshot.playerBuyImpact),
          _impactRow('玩家卖出可吃买盘', snapshot.playerSellImpact),
          if (snapshot.participants.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 9),
              child: Text('当前存档未启用模拟参与者账户',
                  style: TextStyle(fontSize: 11, color: Colors.amberAccent)),
            )
          else ...[
            const SizedBox(height: 10),
            for (final participant in snapshot.participants)
              _participantRow(participant),
          ],
        ]),
      ),
    );
  }

  Widget _participantRow(TxMarketParticipant participant) {
    final flow = participant.minuteNetShares;
    final flowLabel = flow == 0 ? '本分钟无净成交' :
        '本分钟${flow > 0 ? '净买' : '净卖'} ${flow.abs()} '
            '${profile.orderUnit}';
    final roleColor = switch (participant.role) {
      '做市商' => TxTerminalColors.cyan,
      '游资' => TxTerminalColors.primary,
      '中长线资金' => const Color(0xFFE38FE8),
      _ => TxTerminalColors.secondaryText,
    };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: TxTerminalColors.raised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: TxTerminalColors.border),
      ),
      child: Row(children: [
        Container(width: 7, height: 30,
            decoration: BoxDecoration(color: roleColor,
                borderRadius: BorderRadius.circular(5))),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(participant.name, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(participant.role, style: TextStyle(fontSize: 10,
                color: roleColor)),
          ]),
          Text(participant.behaviour,
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
          Text('挂单 ${participant.bidShares}/${participant.askShares} '
              '${profile.orderUnit} · 库存 ${participant.inventoryShares} '
              '${profile.orderUnit} · $flowLabel',
              style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ])),
        Text('${participant.visibleOrders}笔',
            style: const TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
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

  Widget _impactRow(String label, TxMarketBookImpact impact) {
    if (impact.requestedQuantity == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text('$label：当前账户无可执行数量或盘口为空',
            style: const TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
      );
    }
    final vwap = impact.vwapCents == null
        ? '—' : '¥${(impact.vwapCents! / 100).toStringAsFixed(2)}';
    final worst = impact.worstPriceCents == null
        ? '—' : '¥${(impact.worstPriceCents! / 100).toStringAsFixed(2)}';
    final bp = impact.priceImpactBasisPoints == null
        ? '—' : '${impact.priceImpactBasisPoints!.toStringAsFixed(1)} bp';
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text('$label：${impact.executableQuantity}/${impact.requestedQuantity} '
          '${profile.orderUnit} · VWAP $vwap · 最差 $worst · $bp · '
          '${impact.levelsConsumed} 档',
          style: const TextStyle(fontSize: 10,
              color: TxTerminalColors.secondaryText)),
    );
  }
}
