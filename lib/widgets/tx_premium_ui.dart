import 'package:flutter/material.dart';

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
