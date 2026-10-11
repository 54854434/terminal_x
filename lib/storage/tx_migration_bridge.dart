/// V0.1d experimental, explicit JSON-to-SQLite migration bridge.
///
/// NOT connected to lib/main.dart or any Android application's preferences.
/// Callers must provide a *current* snapshot after pausing all trades/writes.
/// No XML, SharedPreferences, Android storage, or old app data is read here.
///
/// This layer deliberately has no fallback that creates a fresh account.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import 'tx_sqlite_store.dart';

class TxMigrationPreview {
  TxMigrationPreview._({
    required String canonicalJson,
    required this.sha256,
    required this.step,
    required this.cashCents,
    required this.reservedCashCents,
    required Map<String, int> shares,
    required Map<String, int> reservedShares,
    required this.playerOrderCount,
    required this.activePlayerOrderCount,
    required this.playerFillCount,
  })  : _canonicalJson = canonicalJson,
        shares = Map.unmodifiable(shares),
        reservedShares = Map.unmodifiable(reservedShares);

  // Retained exclusively in memory. Never log or upload this private content.
  final String _canonicalJson;
  final String sha256;
  final int step;
  final int cashCents;
  final int reservedCashCents;
  final Map<String, int> shares;
  final Map<String, int> reservedShares;
  final int playerOrderCount;
  final int activePlayerOrderCount;
  final int playerFillCount;
}

class TxMigrationResult {
  const TxMigrationResult({
    required this.session,
    required this.revision,
    required this.alreadyMigrated,
  });

  final TxSession session;
  final int revision;
  // True only when SQLite already contained a valid session at confirmation.
  final bool alreadyMigrated;
}

class TxMigrationBridge {
  static String _validatedCanonicalJson(String source) {
    final session = TxSession.importJson(source);
    session.engine.checkInvariants();
    return session.exportJson();
  }

  static String _sha(String canonical) =>
      sha256.convert(utf8.encode(canonical)).toString();

  /// Pure read-only preview. In particular, does NOT open or initialize SQLite.
  static TxMigrationPreview previewJson(String sourceJson) {
    final canonical = _validatedCanonicalJson(sourceJson);
    final session = TxSession.importJson(canonical);
    final player = session.engine.account(TxSession.playerId);
    final orders = session.playerOrders;
    return TxMigrationPreview._(
      canonicalJson: canonical,
      sha256: _sha(canonical),
      step: session.step,
      cashCents: player.cashCents,
      reservedCashCents: player.reservedCashCents,
      shares: {for (final s in TxSession.symbols) s: player.sharesOf(s)},
      reservedShares: {
        for (final s in TxSession.symbols) s: player.reservedSharesOf(s),
      },
      playerOrderCount: orders.length,
      activePlayerOrderCount: orders.where((o) =>
          o.status == TxStatus.open || o.status == TxStatus.partiallyFilled).length,
      playerFillCount: session.playerFills.length,
    );
  }

  /// Explicit confirmation; no automatic migration on application startup.
  ///
  /// The caller is responsible for pausing trades/queued writes, then obtaining
  /// currentSourceJson AGAIN immediately before calling this method. If the
  /// previewed snapshot changed, migration fails without touching SQLite.
  /// On a repeated request using the same original source, the underlying
  /// store returns the current revision (including any later SQLite trades).
  static Future<TxMigrationResult> confirmJson({
    required TxSqliteStore store,
    required TxMigrationPreview preview,
    required String currentSourceJson,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw StateError('Migration requires explicit user confirmation');
    }

    // Check BEFORE any SQLite writes, not just at preview time.
    final canonical = _validatedCanonicalJson(currentSourceJson);
    if (_sha(canonical) != preview.sha256 ||
        canonical != preview._canonicalJson) {
      throw StateError('Source changed after preview; inspect it again');
    }

    // Throws instead of creating a fresh session if a stored record is invalid.
    final before = await store.readCurrent();
    final migrated = await store.migrateFromPreferencesSnapshot(canonical);
    final reloaded = await store.readCurrent();
    if (reloaded == null ||
        reloaded.sha256 != migrated.sha256 ||
        reloaded.revision != migrated.revision ||
        reloaded.session.exportJson() != migrated.session.exportJson()) {
      throw StateError('SQLite migration read-back verification failed');
    }
    reloaded.session.engine.checkInvariants();
    if (before == null &&
        (reloaded.revision != 1 ||
         reloaded.sha256 != preview.sha256 ||
         reloaded.session.exportJson() != canonical)) {
      throw StateError('New SQLite migration did not match the preview');
    }

    return TxMigrationResult(
      session: reloaded.session,
      revision: reloaded.revision,
      alreadyMigrated: before != null,
    );
  }
}
