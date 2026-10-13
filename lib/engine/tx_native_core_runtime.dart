/// R37 native-runtime verification; isolated from the authoritative trader.
/// This probe executes a real filled trade in the ARM64 Rust library, then
/// releases it. It NEVER reads or mutates a player session or a SQLite file.
import 'dart:isolate';

import 'tx_native_core_ffi.dart';

String _runNativeSelfTest() {
  TxNativeCoreFfi? rust;
  try {
    rust = TxNativeCoreFfi.openInstalledAndroidLibrary();
    if (rust.registerAccount(id: 1001, cashCents: 100000,
            simA01Shares: 0, simA02Shares: 0) != 0 ||
        rust.registerAccount(id: 1002, cashCents: 0,
            simA01Shares: 10, simA02Shares: 0) != 0) {
      throw StateError('native account registration failed');
    }
    if (rust.place(orderId: 201, ownerId: 1002, symbol: 0,
            side: TxNativeCoreFfi.sell, kind: TxNativeCoreFfi.limit,
            quantity: 3, priceCents: 1000) != TxNativeCoreFfi.openStatus ||
        rust.place(orderId: 202, ownerId: 1001, symbol: 0,
            side: TxNativeCoreFfi.buy, kind: TxNativeCoreFfi.limit,
            quantity: 2, priceCents: 1000) != TxNativeCoreFfi.filled) {
      throw StateError('native limit matching failed');
    }
    if (rust.fillCount != 1 || rust.fillPrice(0) != 1000 ||
        rust.fillQuantity(0) != 2 || rust.cashCents(1001) != 98000 ||
        rust.cashCents(1002) != 2000 || rust.shares(1001, 0) != 2 ||
        rust.shares(1002, 0) != 8 || rust.reservedShares(1002, 0) != 1 ||
        !rust.isAudited) {
      throw StateError('native account/ledger audit failed');
    }
    final rebuilt = rust.rebuildFromEvents();
    try {
      if (!rebuilt.isAudited || rebuilt.fillCount != 1 ||
          rebuilt.cashCents(1001) != 98000 ||
          rebuilt.reservedShares(1002, 0) != 1) {
        throw StateError('native replay differed from source');
      }
    } finally {
      rebuilt.close();
    }
    return 'ABI v2 已装载，真实撮合与重放通过（对照模式）';
  } catch (error) {
    // Fail visibly but do not touch the production Dart engine or save.
    return '不可用：$error';
  } finally {
    rust?.close();
  }
}

class TxNativeCoreRuntime {
  const TxNativeCoreRuntime._();
  /// The native library and its opaque pointers are created within one isolate.
  static Future<String> probeAndroid() => Isolate.run(_runNativeSelfTest);
}
