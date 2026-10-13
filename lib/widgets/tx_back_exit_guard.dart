import 'package:flutter/material.dart';

/// Prevent Android system Back from silently terminating the simulator.
/// Every back request is routed to the owning game screen. The owner decides
/// whether to navigate within the app, pause, or ask for explicit exit.
class TxBackExitGuard extends StatelessWidget {
  const TxBackExitGuard({super.key, required this.onBack,
      required this.child});

  final Future<void> Function() onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) onBack();
    },
    child: child,
  );
}
