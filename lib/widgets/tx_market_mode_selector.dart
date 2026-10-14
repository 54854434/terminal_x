import 'package:flutter/material.dart';

import '../market/tx_market_profiles.dart';
import '../market/tx_market_session_schedule.dart';
import 'tx_terminal_theme.dart';

/// A visible market-mode switch. Only the A-share spot profile is connected
/// to the current matching core; other profiles are honest rule previews.
class TxMarketModeSelector extends StatelessWidget {
  const TxMarketModeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.gameDay = 1,
    this.minuteOfDay = 570,
  });

  final TxMarketMode selected;
  final ValueChanged<TxMarketMode> onSelected;
  final int gameDay;
  final int minuteOfDay;

  @override
  Widget build(BuildContext context) {
    final profile = TxMarketProfile.of(selected);
    final sessionStatus = profile.schedule.status(
        gameDay: gameDay, minuteOfDay: minuteOfDay);
    final statusColor = switch (sessionStatus.state) {
      TxMarketSessionState.open => TxTerminalColors.buy,
      TxMarketSessionState.breakTime => Colors.amberAccent,
      TxMarketSessionState.closed => TxTerminalColors.secondaryText,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            const Icon(Icons.language_outlined, size: 18,
                color: TxTerminalColors.primary),
            const SizedBox(width: 7),
            const Expanded(child: Text('市场模式',
                style: TextStyle(fontWeight: FontWeight.w700))),
            Text(profile.category, style: const TextStyle(fontSize: 10,
                color: TxTerminalColors.secondaryText)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 5, children: [
            for (final item in TxMarketProfile.values)
              ChoiceChip(
                label: Text(item.label, style: const TextStyle(fontSize: 11)),
                selected: item.mode == selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelected(item.mode),
              ),
          ]),
          const SizedBox(height: 7),
          Wrap(spacing: 6, runSpacing: 5, children: [
            _chip(profile.quoteCurrency, TxTerminalColors.primary),
            _chip(profile.orderUnit, TxTerminalColors.secondaryText),
            _chip(profile.tickSize, TxTerminalColors.cyan),
            _chip(profile.maxLeverage, profile.supportsShort
                ? const Color(0xFFE38FE8)
                : TxTerminalColors.secondaryText),
            _chip('${profile.instruments.length} 个模拟标的',
                TxTerminalColors.secondaryText),
          ]),
          const SizedBox(height: 5),
          Text('${profile.session} · ${profile.settlement}',
              style: const TextStyle(fontSize: 10,
                  color: TxTerminalColors.secondaryText)),
          const SizedBox(height: 3),
          Row(children: [
            Icon(sessionStatus.isOpen ? Icons.radio_button_checked
                : Icons.pause_circle_outline, size: 14, color: statusColor),
            const SizedBox(width: 5),
            Text('规则时段：${sessionStatus.label}',
                style: TextStyle(fontSize: 10, color: statusColor)),
            if (sessionStatus.minutesToTransition != null) ...[
              const SizedBox(width: 6),
              Text('${sessionStatus.minutesToTransition} 分钟后变化',
                  style: const TextStyle(fontSize: 10,
                      color: TxTerminalColors.secondaryText)),
            ],
          ]),
          const SizedBox(height: 3),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(profile.isCoreConnected ? Icons.check_circle_outline
                : Icons.construction_outlined, size: 15,
                color: profile.isCoreConnected
                    ? TxTerminalColors.buy : Colors.amberAccent),
            const SizedBox(width: 5),
            Expanded(child: Text(profile.coreStatus,
                style: TextStyle(fontSize: 10,
                    color: profile.isCoreConnected
                        ? TxTerminalColors.buy : Colors.amberAccent))),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withAlpha(95)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );
}
