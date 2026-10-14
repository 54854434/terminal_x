import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

/// The visual language is shared across the four offline trading screens.
/// Colors distinguish buy/sell and indicative data, never guarantee profit.
class TxTerminalColors {
  const TxTerminalColors._();
  static const background = Color(0xFF090F19);
  static const surface = Color(0xFF121D2B);
  static const surfaceElevated = Color(0xFF17263A);
  static const raised = Color(0xFF19283A);
  static const border = Color(0xFF2A3A4E);
  static const primary = Color(0xFF81ACFF);
  static const cyan = Color(0xFF63DEEE);
  static const gold = Color(0xFFE6C675);
  static const buy = Color(0xFF3DD3A5);
  static const sell = Color(0xFFFF707A);
  static const textPrimary = Color(0xFFE7EDF6);
  static const secondaryText = Color(0xFFA6B5C9);
}

class TxTerminalTheme {
  const TxTerminalTheme._();
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    const rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      side: BorderSide(color: TxTerminalColors.border));
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)));
    return base.copyWith(
      scaffoldBackgroundColor: TxTerminalColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TxTerminalColors.primary,
        brightness: Brightness.dark).copyWith(
          primary: TxTerminalColors.primary,
          surface: TxTerminalColors.surface,
          error: TxTerminalColors.sell),
      textTheme: base.textTheme.apply(
        bodyColor: TxTerminalColors.textPrimary,
        displayColor: TxTerminalColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TxTerminalColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16),
      cardTheme: const CardThemeData(
        color: TxTerminalColors.surface, shape: rounded,
        elevation: 0, margin: EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias),
      dividerTheme: const DividerThemeData(
        color: TxTerminalColors.border,
        thickness: 1,
        space: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        iconColor: TxTerminalColors.secondaryText),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: TxTerminalColors.surface,
        indicatorColor: TxTerminalColors.raised,
        height: 74,
        elevation: 8,
        surfaceTintColor: Colors.transparent),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: buttonShape)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: TxTerminalColors.border),
          shape: buttonShape)),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: TxTerminalColors.raised,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: TxTerminalColors.border)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: TxTerminalColors.border)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: TxTerminalColors.primary, width: 1.5))),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: TxTerminalColors.surfaceElevated,
        contentTextStyle: TextStyle(color: TxTerminalColors.textPrimary),
        behavior: SnackBarBehavior.floating),
    );
  }
}

/// A compact, consistently styled read-only number tile.
class TxMetricTile extends StatelessWidget {
  const TxMetricTile({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: Padding(padding: const EdgeInsets.all(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TxTerminalColors.raised,
          border: Border.all(color: TxTerminalColors.border),
          borderRadius: BorderRadius.circular(10)),
        child: Padding(padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TxTerminalColors.secondaryText, fontSize: 11)),
              const SizedBox(height: 5),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
            ]))),
      ),
  );
}
