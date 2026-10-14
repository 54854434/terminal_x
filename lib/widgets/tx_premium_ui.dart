import 'package:flutter/material.dart';

import '../engine/tx_engine.dart';
import '../market/tx_market_profiles.dart';
import '../market/tx_market_session_schedule.dart';
import '../market/tx_order_book_insight.dart';
import 'tx_terminal_theme.dart';

/// Shared presentation primitives for the five player-facing workspaces.
///
/// These widgets intentionally contain no market or account state. They only
/// make the information hierarchy consistent: page identity first, then a
/// short explanation, then the operational cards below it.
class TxPageHeader extends StatelessWidget {
  const TxPageHeader({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.status,
    this.accent = TxTerminalColors.primary,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String? status;
  final Color accent;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 5),
    clipBehavior: Clip.antiAlias,
    child: Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(TxTerminalColors.surface, accent, .12)!,
            TxTerminalColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(top: BorderSide(color: accent.withAlpha(150))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withAlpha(35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withAlpha(105)),
            ),
            child: Icon(icon, color: accent, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: TxTerminalColors.secondaryText,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withAlpha(85)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          status!,
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A compact section label used before each logical information group.
class TxSectionHeader extends StatelessWidget {
  const TxSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent = TxTerminalColors.primary,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 17, 4, 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: subtitle == null ? 21 : 34,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        if (icon != null) ...[
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .15,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: TxTerminalColors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Small explanatory strip for notes that should not compete with metrics.
class TxInfoStrip extends StatelessWidget {
  const TxInfoStrip({
    super.key,
    required this.icon,
    required this.text,
    this.accent = TxTerminalColors.secondaryText,
  });

  final IconData icon;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: accent.withAlpha(15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withAlpha(45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A compact market switcher shared by the market, trading, portfolio and
/// records workspaces. It deliberately shows every board in one place so a
/// user can inspect another account without first returning to the quote page.
class TxMarketContextStrip extends StatelessWidget {
  const TxMarketContextStrip({
    super.key,
    required this.selected,
    required this.gameDay,
    required this.minuteOfDay,
    required this.onSelected,
    this.enabled = true,
  });

  final TxMarketMode selected;
  final int gameDay;
  final int minuteOfDay;
  final ValueChanged<TxMarketMode> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final openCount = TxMarketProfile.values.where((profile) => profile.schedule
        .status(gameDay: gameDay, minuteOfDay: minuteOfDay).isOpen).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.swap_horizontal_circle_outlined,
                size: 18, color: TxTerminalColors.cyan),
            const SizedBox(width: 7),
            const Expanded(child: Text('市场台 · 独立账户切换',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            Text('$openCount/${TxMarketProfile.values.length} 开市',
                style: const TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: TxMarketProfile.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final profile = TxMarketProfile.values[index];
                final status = profile.schedule.status(
                    gameDay: gameDay, minuteOfDay: minuteOfDay);
                final isSelected = profile.mode == selected;
                final accent = _statusColor(status.state);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: 94,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withAlpha(32)
                        : TxTerminalColors.raised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected
                            ? accent.withAlpha(190)
                            : TxTerminalColors.border),
                    boxShadow: isSelected
                        ? [BoxShadow(color: accent.withAlpha(35), blurRadius: 10)]
                        : const [],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: enabled ? () => onSelected(profile.mode) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(child: Text(profile.label,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w800 : FontWeight.w600))),
                          if (isSelected)
                            Icon(Icons.check_circle, size: 14, color: accent),
                        ]),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Row(
                            key: ValueKey<String>(status.state.name),
                            children: [
                              Container(width: 7, height: 7,
                                  decoration: BoxDecoration(
                                      color: accent, shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Expanded(child: Text(status.label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: accent))),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  static Color _statusColor(TxMarketSessionState state) => switch (state) {
    TxMarketSessionState.open => TxTerminalColors.buy,
    TxMarketSessionState.breakTime => TxTerminalColors.gold,
    TxMarketSessionState.closed => TxTerminalColors.secondaryText,
  };
}

/// Small, explicit switches for the player-position lines painted over a K
/// chart. The calculation remains in the account/risk layer; this widget only
/// controls what the player wants to see.
class TxChartOverlayToggleBar extends StatelessWidget {
  const TxChartOverlayToggleBar({
    super.key,
    required this.showCost,
    required this.showBreakeven,
    required this.showLiquidation,
    required this.onCostChanged,
    required this.onBreakevenChanged,
    required this.onLiquidationChanged,
  });

  final bool showCost;
  final bool showBreakeven;
  final bool showLiquidation;
  final ValueChanged<bool> onCostChanged;
  final ValueChanged<bool> onBreakevenChanged;
  final ValueChanged<bool> onLiquidationChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    runSpacing: 3,
    children: [
      FilterChip(
        label: const Text('成本 / 收益', style: TextStyle(fontSize: 10)),
        selected: showCost,
        visualDensity: VisualDensity.compact,
        onSelected: onCostChanged,
      ),
      FilterChip(
        label: const Text('盈亏平衡', style: TextStyle(fontSize: 10)),
        selected: showBreakeven,
        visualDensity: VisualDensity.compact,
        onSelected: onBreakevenChanged,
      ),
      FilterChip(
        label: const Text('强平线', style: TextStyle(fontSize: 10)),
        selected: showLiquidation,
        visualDensity: VisualDensity.compact,
        onSelected: onLiquidationChanged,
      ),
    ],
  );
}

/// One order-book presentation for every market. Ten levels are intentionally
/// rendered as two parallel columns: best prices stay near the chart while the
/// remaining depth is still visible without a second market-specific layout.
class TxUnifiedOrderBook extends StatelessWidget {
  const TxUnifiedOrderBook({
    super.key,
    required this.bids,
    required this.asks,
    required this.priceLabel,
    this.title = '十档盘口',
    this.subtitle = '真实挂单快照 · 点击价位填入限价',
    this.onPrice,
  });

  final List<TxBookLevel> bids;
  final List<TxBookLevel> asks;
  final String Function(int cents) priceLabel;
  final String title;
  final String subtitle;
  final void Function(TxSide side, int priceCents)? onPrice;

  @override
  Widget build(BuildContext context) {
    final insight = TxOrderBookInsight.fromLevels(bids: bids, asks: asks);
    final maxQuantity = [...bids, ...asks, const TxBookLevel(0, 1, 1)]
        .map((level) => level.quantity)
        .reduce(mathMax);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.view_list_rounded, size: 18,
                color: TxTerminalColors.cyan),
            const SizedBox(width: 7),
            Expanded(child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(insight.spreadCents == null
                ? '价差 —'
                : '价差 ${priceLabel(insight.spreadCents!)}',
                style: const TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
          ]),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 10,
              color: TxTerminalColors.secondaryText)),
          const SizedBox(height: 7),
          if (insight.bidShareFraction != null)
            Row(children: [
              const Text('买卖深度', style: TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
              const SizedBox(width: 7),
              Expanded(child: LinearProgressIndicator(
                  value: insight.bidShareFraction,
                  minHeight: 4,
                  backgroundColor: TxTerminalColors.sell,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      TxTerminalColors.buy))),
              const SizedBox(width: 7),
              Text('${(insight.bidShareFraction! * 100).toStringAsFixed(0)}% 买盘',
                  style: const TextStyle(fontSize: 10,
                      color: TxTerminalColors.secondaryText)),
            ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _column(
                title: '买盘 Bids', levels: bids, color: TxTerminalColors.buy,
                side: TxSide.buy, maxQuantity: maxQuantity)),
            const SizedBox(width: 10),
            Expanded(child: _column(
                title: '卖盘 Asks', levels: asks, color: TxTerminalColors.sell,
                side: TxSide.sell, maxQuantity: maxQuantity)),
          ]),
          const SizedBox(height: 5),
          Text('买 ${insight.bidShares} · 卖 ${insight.askShares} · '
              '${insight.bidOrders + insight.askOrders} 笔挂单 · 只来自本地真实订单簿',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
      ),
    );
  }

  Widget _column({
    required String title,
    required List<TxBookLevel> levels,
    required Color color,
    required TxSide side,
    required int maxQuantity,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: TextStyle(color: color, fontSize: 11,
        fontWeight: FontWeight.w800)),
    const SizedBox(height: 3),
    if (levels.isEmpty)
      const Padding(padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('暂无挂单', style: TextStyle(fontSize: 11))),
    for (var i = 0; i < mathMin(10, levels.length); i++)
      InkWell(
        onTap: onPrice == null
            ? null : () => onPrice!(side, levels[i].priceCents),
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 25,
          child: Stack(children: [
            Align(alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (levels[i].quantity / maxQuantity)
                    .clamp(0.0, 1.0).toDouble(),
                child: Container(height: 19,
                    decoration: BoxDecoration(
                      color: color.withAlpha(24),
                      borderRadius: BorderRadius.circular(4),
                    )),
            )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Row(children: [
                SizedBox(width: 20, child: Text('${i + 1}',
                    style: TextStyle(fontSize: 9, color: color))),
                Expanded(child: Text(priceLabel(levels[i].priceCents),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: color))),
                Text('${levels[i].quantity}', style: const TextStyle(
                    fontSize: 10, color: Colors.white70)),
              ]),
            ),
          ]),
        ),
      ),
  ]);
}

int mathMax(int a, int b) => a > b ? a : b;
int mathMin(int a, int b) => a < b ? a : b;
