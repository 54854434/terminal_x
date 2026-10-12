/// Fail-closed trading service: no proposed trade is visible before its
/// checksummed SQLite transaction commits. Legacy account files stay intact.
import 'dart:isolate';

import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import '../market/tx_market_event_tape.dart';
import 'tx_sqlite_store.dart';

// Pure Dart market evaluation is moved away from the Flutter UI isolate.
// The authoritative session is never mutated: the isolate gets a serialized
// copy, and only the returned candidate can be committed.
TxSession _advanceMinute(TxSession session) {
  // Isolate.run copies this pure-Dart object graph to a worker isolate.
  // Neither the persisted nor the UI-visible source instance is mutated.
  // Avoid serializing the entire growing order/ledger history on the UI thread.
  session.nextTick();
  return session;
}

/// Isolate proposals keep the original session immutable until SQLite commit.
class _TradeProposal {
  const _TradeProposal(this.session, this.orderId);
  final TxSession session;
  final String orderId;
}

_TradeProposal _placeOnWorker(
    TxSession original, String symbol, TxSide side, TxKind kind,
    int quantity, int? limitPriceCents) {
  final proposed = TxSession.importJson(original.exportJson());
  final order = proposed.placePlayer(
    symbol: symbol, side: side, kind: kind, quantity: quantity,
    limitPriceCents: limitPriceCents);
  return _TradeProposal(proposed, order.id);
}

_TradeProposal _cancelOnWorker(TxSession original, String orderId) {
  final proposed = TxSession.importJson(original.exportJson());
  final order = proposed.cancelPlayer(orderId);
  return _TradeProposal(proposed, order.id);
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
      // Fast existing-account path: don't allocate/validate a fresh market
      // (including 6 simulated accounts and its order book) on every reopen.
      // readCurrent throws on damage; NEVER treat corruption as an empty DB.
      final loaded = await database.readCurrent() ??
          await database.initializeFresh(_initialSessionFactory());
      // readCurrent/initializeFresh verify checksums and full engine ledgers.
      _current = loaded;
      return loaded;
    } catch (_) {
      _storageFault = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// User actions use the same isolated clone-then-commit principle as ticks.
  /// Their expanding JSON history no longer serializes on the Flutter thread.
  Future<TxOrder> place({
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    int? limitPriceCents,
  }) async {
    _ensureReady();
    _busy = true;
    try {
      final source = current.session;
      final proposal = await Isolate.run(() => _placeOnWorker(
        source, symbol, side, kind, quantity, limitPriceCents));
      await _commit(proposal.session);
      return current.session.engine.order(proposal.orderId);
    } finally {
      _busy = false;
    }
  }

  Future<TxOrder> cancel(String orderId) async {
    _ensureReady();
    _busy = true;
    try {
      final source = current.session;
      final proposal = await Isolate.run(
        () => _cancelOnWorker(source, orderId));
      await _commit(proposal.session);
      return current.session.engine.order(proposal.orderId);
    } finally {
      _busy = false;
    }
  }

  /// Capture only genuine matched trades from consecutive committed revisions.
  /// Callers may use this for replay/diagnostics; an ordinal is not a timestamp.
  Future<TxMinuteEventTape> nextTickWithTape() async {
    final before = current;
    final after = await nextTick();
    return TxMinuteEventTape.fromCommits(before, after);
  }

  Future<TxStoredSession> nextTick() async {
    _ensureReady();
    // Isolation prevents the order-book matching and NPC computations from
    // blocking a chart drag or animation. No skipped or speculative minutes.
    // Serialization and SQLite checksum checks remain a measurable P1 cost.
    _busy = true; // Reserve the revision during the worker's computation.
    try {
      // The isolate receives an independent copy of this sendable pure-Dart
      // graph; no main-isolate exportJson() per minute. SQLite still audits,
      // hashes and commits the returned candidate before it is made visible.
      final source = current.session;
      final candidate = await Isolate.run(() => _advanceMinute(source));
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
