import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../engine/tx_engine.dart';
import '../market/tx_market_profiles.dart';
import '../market/tx_market_session_schedule.dart';
import '../market/tx_market_microstructure.dart';
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

/// Read-only quote used by the cross-market desk. The market page owns the
/// calculations; this view model keeps the presentation identical for the
/// connected A-share engine and the independent venues.
class TxMarketDeskQuote {
  const TxMarketDeskQuote({
    required this.mode,
    required this.label,
    required this.symbol,
    required this.status,
    required this.mark,
    required this.change,
    required this.activity,
    required this.liquidity,
    required this.account,
    required this.isOpen,
    required this.isLoaded,
    required this.isSelected,
    required this.accent,
    this.pressure,
  });

  final TxMarketMode mode;
  final String label;
  final String symbol;
  final String status;
  final String mark;
  final String change;
  final String activity;
  final String liquidity;
  final String account;
  final bool isOpen;
  final bool isLoaded;
  final bool isSelected;
  final Color accent;
  final double? pressure;
}

/// A professional multi-market overview that stays compact enough to keep the
/// selected K-line near the first viewport. It is deliberately a horizontal
/// desk, not a second navigation page: tap any board to switch its account,
/// chart and order book in place.
class TxMarketDeskOverview extends StatelessWidget {
  const TxMarketDeskOverview({
    super.key,
    required this.quotes,
    required this.onSelected,
  });

  final List<TxMarketDeskQuote> quotes;
  final ValueChanged<TxMarketMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final open = quotes.where((quote) => quote.isOpen).length;
    final loaded = quotes.where((quote) => quote.isLoaded).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined,
                    size: 18, color: TxTerminalColors.cyan),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text('多市场专业工作台',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text('$open/${quotes.length} 开市 · $loaded 已连接',
                    style: const TextStyle(
                        fontSize: 10, color: TxTerminalColors.secondaryText)),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
                '价格、涨跌、成交、可见流动性和账户权益统一呈现；休市板块冻结，已开市板块可直接切换。',
                style: TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
            const SizedBox(height: 9),
            SizedBox(
              height: 142,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: quotes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) => _tile(quotes[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(TxMarketDeskQuote quote) {
    final selectedBorder = quote.isSelected
        ? TxTerminalColors.cyan.withAlpha(210)
        : quote.accent.withAlpha(75);
    final changeColor = quote.change.startsWith('+')
        ? TxTerminalColors.buy
        : quote.change.startsWith('-')
            ? TxTerminalColors.sell
            : TxTerminalColors.secondaryText;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 164,
      decoration: BoxDecoration(
        color: quote.isSelected
            ? TxTerminalColors.surfaceElevated
            : TxTerminalColors.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selectedBorder,
            width: quote.isSelected ? 1.4 : 1),
        boxShadow: quote.isSelected
            ? [BoxShadow(color: TxTerminalColors.cyan.withAlpha(28),
                blurRadius: 12)]
            : const [],
      ),
      child: InkWell(
        onTap: () => onSelected(quote.mode),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(quote.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                  if (quote.isSelected)
                    const Icon(Icons.radio_button_checked, size: 13,
                        color: TxTerminalColors.cyan),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: quote.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(quote.status,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: quote.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(quote.mark,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Row(
                children: [
                  Expanded(child: Text(quote.symbol,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9,
                          color: TxTerminalColors.secondaryText))),
                  Text(quote.change,
                      style: TextStyle(fontSize: 10,
                          color: changeColor, fontWeight: FontWeight.w700)),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: Text(quote.activity,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9,
                          color: TxTerminalColors.secondaryText))),
                  Text(quote.liquidity,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9,
                          color: TxTerminalColors.secondaryText)),
                ],
              ),
              const SizedBox(height: 2),
              Text('账户 ${quote.account}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9,
                      color: TxTerminalColors.secondaryText)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared tape and pressure panel for every market. It distinguishes actual
/// matched prints from resting depth, so a large visible book is not silently
/// presented as buying or selling pressure.
class TxMarketFlowPanel extends StatelessWidget {
  const TxMarketFlowPanel({
    super.key,
    required this.snapshot,
    required this.priceLabel,
    required this.quantityUnit,
    this.title = '实时成交与盘口压力',
    this.subtitle = '最近真实成交 · 主动买卖量 · 十档可见深度',
  });

  final TxMarketMicrostructureSnapshot snapshot;
  final String Function(int cents) priceLabel;
  final String quantityUnit;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final pressure = snapshot.buyPressure;
    final pressureLabel = pressure == null
        ? '暂无主动方向'
        : '主动买 ${(pressure * 100).toStringAsFixed(0)}%';
    final spread = snapshot.spreadCents == null
        ? '—' : priceLabel(snapshot.spreadCents!);
    final last = snapshot.lastTradePriceCents == null
        ? '—' : priceLabel(snapshot.lastTradePriceCents!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 18,
                    color: TxTerminalColors.gold),
                const SizedBox(width: 7),
                Expanded(child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
                Text('${snapshot.printCount} 笔真实成交',
                    style: const TextStyle(fontSize: 10,
                        color: TxTerminalColors.secondaryText)),
              ],
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
            const SizedBox(height: 9),
            Row(
              children: [
                _metric('主动买', '${snapshot.buyVolume}$quantityUnit',
                    TxTerminalColors.buy),
                _metric('主动卖', '${snapshot.sellVolume}$quantityUnit',
                    TxTerminalColors.sell),
                _metric('成交总量', '${snapshot.totalVolume}$quantityUnit',
                    TxTerminalColors.primary),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                const Text('主动成交压力', style: TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    // An empty window is a real "no direction" state. Keep
                    // it static instead of showing an indeterminate spinner
                    // that could be mistaken for live buying pressure.
                    value: pressure == null
                        ? 0.0 : pressure.clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: TxTerminalColors.sell.withAlpha(155),
                    valueColor: AlwaysStoppedAnimation<Color>(pressure == null
                        ? TxTerminalColors.secondaryText
                        : TxTerminalColors.buy),
                  ),
                ),
                const SizedBox(width: 8),
                Text(pressureLabel, style: const TextStyle(fontSize: 10,
                    color: TxTerminalColors.secondaryText)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _microLabel('最新成交', last),
                _microLabel('买卖价差', spread),
                _microLabel('十档深度', '${snapshot.visibleDepth}$quantityUnit'),
              ],
            ),
            const SizedBox(height: 7),
            const Divider(height: 1),
            const SizedBox(height: 6),
            const Text('最近成交', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700)),
            if (snapshot.prints.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('当前窗口没有已发生的真实成交；盘口报价不会伪造成交。',
                    style: TextStyle(fontSize: 10,
                        color: TxTerminalColors.secondaryText)),
              )
            else
              for (final print in snapshot.prints.reversed.take(6))
                _printRow(print),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9,
                color: TxTerminalColors.secondaryText)),
        const SizedBox(height: 3),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: color,
                fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  Widget _microLabel(String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 10,
          color: TxTerminalColors.secondaryText)),
      Text(' $value', style: const TextStyle(fontSize: 10,
          fontWeight: FontWeight.w700)),
    ],
  );

  Widget _printRow(TxMarketPrint print) {
    final isBuy = print.aggressor == TxMarketAggressor.buy;
    final isSell = print.aggressor == TxMarketAggressor.sell;
    final color = isBuy ? TxTerminalColors.buy
        : isSell ? TxTerminalColors.sell : TxTerminalColors.secondaryText;
    final action = isBuy ? '主动买' : isSell ? '主动卖' : '方向未知';
    final actor = print.aggressorLabel == null
        ? '' : ' · ${print.aggressorLabel}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          SizedBox(width: 45, child: Text(action,
              style: TextStyle(fontSize: 10, color: color,
                  fontWeight: FontWeight.w700))),
          Expanded(child: Text('${print.quantity}$quantityUnit · '
              '${priceLabel(print.priceCents)}$actor',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10))),
          Text(print.timeLabel ?? '—', style: const TextStyle(fontSize: 9,
              color: TxTerminalColors.secondaryText)),
        ],
      ),
    );
  }
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
