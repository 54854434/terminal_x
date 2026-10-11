/// Fail-closed trading service for the NEW V0.1d SQLite-only simulator.
///
/// Every operation works on a defensive session clone. The displayed state is
/// advanced only AFTER the SQLite transaction commits successfully. A storage
/// exception disables further trades until the app has been reopened and the
/// database revalidated. No legacy preferences or backup files are read.
import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import 'tx_sqlite_store.dart';

class TxTradingService {
  TxTradingService(this.database);

  final TxSqliteStore database;
  TxStoredSession? _current;
  bool _busy = false;
  bool _storageFault = false;

  TxStoredSession get current {
    if (_current == null) throw StateError('SQLite session not initialized');
    return _current!;
  }

  bool get blocked => _storageFault;

  Future<TxStoredSession> open() async {
    if (_current != null) return current;
    if (_busy) throw StateError('Storage is busy');
    _busy = true;
    try {
      // initializeFresh itself checks for an existing account and never resets
      // one. A damaged existing database throws rather than silently resetting.
      final loaded = await database.initializeFresh(TxSession.fresh());
      loaded.session.engine.checkInvariants();
      _current = loaded;
      return loaded;
    } catch (_) {
      _storageFault = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<TxOrder> place({
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    int? limitPriceCents,
  }) async {
    _ensureReady();
    final proposed = TxSession.importJson(current.session.exportJson());
    final order = proposed.placePlayer(
      symbol: symbol,
      side: side,
      kind: kind,
      quantity: quantity,
      limitPriceCents: limitPriceCents,
    );
    await _commit(proposed);
    return order;
  }

  Future<TxOrder> cancel(String orderId) async {
    _ensureReady();
    final proposed = TxSession.importJson(current.session.exportJson());
    final order = proposed.cancelPlayer(orderId);
    await _commit(proposed);
    return order;
  }

  Future<TxStoredSession> nextTick() async {
    _ensureReady();
    final proposed = TxSession.importJson(current.session.exportJson());
    proposed.nextTick();
    await _commit(proposed);
    return current;
  }

  void _ensureReady() {
    if (_storageFault) {
      throw StateError('SQLite storage error: reopen and verify before trading');
    }
    if (_busy) throw StateError('A save is already in progress');
    if (_current == null) throw StateError('Session has not loaded');
  }

  Future<void> _commit(TxSession candidate) async {
    _busy = true;
    try {
      candidate.engine.checkInvariants();
      final saved = await database.saveSession(
        candidate,
        expectedRevision: current.revision,
      );
      // No display/UI mutations happen until the transaction is committed.
      _current = saved;
    } catch (_) {
      // A failed or ambiguously completed storage operation must not be
      // followed by another order using a potentially stale revision.
      _storageFault = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() => database.close();
}
