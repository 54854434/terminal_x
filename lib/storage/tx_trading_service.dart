/// Fail-closed trading service: no proposed trade is visible before its
/// checksummed SQLite transaction commits. Legacy account files stay intact.
import 'dart:isolate';

import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import 'tx_sqlite_store.dart';

// Pure Dart market evaluation is moved away from the Flutter UI isolate.
// The authoritative session is never mutated: the isolate gets a serialized
// copy, and only the returned candidate can be committed.
TxSession _advanceMinute(String snapshot) {
  final candidate = TxSession.importJson(snapshot);
  candidate.nextTick();
  return candidate;
}

class TxTradingService {
  TxTradingService(this.database, {TxSession Function()? initialSessionFactory})
      : _initialSessionFactory = initialSessionFactory ?? TxSession.fresh;

  final TxSqliteStore database;
  final TxSession Function() _initialSessionFactory;
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
      final loaded = await database.initializeFresh(_initialSessionFactory());
      // initializeFresh/readCurrent already verifies the engine and checksum.
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
      symbol: symbol, side: side, kind: kind, quantity: quantity,
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
    // Isolation prevents the order-book matching and NPC computations from
    // blocking a chart drag or animation. No skipped or speculative minutes.
    // Serialization and SQLite checksum checks remain a measurable P1 cost.
    _busy = true; // Reserve the revision during the worker's computation.
    try {
      final snapshot = current.session.exportJson();
      final candidate = await Isolate.run(() => _advanceMinute(snapshot));
      await _commit(candidate);
      return current;
    } finally {
      _busy = false;
    }
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
      // TxSqliteStore.saveSession canonicalizes, checks the ledger and
      // verifies the persisted revision before returning. Avoid duplicating
      // another full audit here on the rendering isolate.
      final saved = await database.saveSession(
        candidate, expectedRevision: current.revision,
      );
      _current = saved;
    } catch (_) {
      _storageFault = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() => database.close();
}
