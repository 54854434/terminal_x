/// Fail-closed trading service. Private market calculations are isolated from
/// the UI; only SQLite-committed revisions become visible or actionable.
import 'dart:isolate';

import '../engine/tx_engine.dart';
import '../engine/tx_session.dart';
import '../market/tx_market_event_tape.dart';
import 'tx_persistent_market_worker.dart';
import 'tx_sqlite_store.dart';

TxSession _advanceMinute(TxSession session) {
  session.nextTick();
  return session;
}

TxSession _advancePulse(TxSession session, int second) {
  session.marketPulse(second);
  return session;
}

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

// Top-level isolate entry wrappers must not capture TxTradingService `this`.
// A TxSqliteStore contains unsendable sqlite3 FFI pointers; sending it in a
// closure would fail every trade and minute tick before the DB transaction.
Future<_TradeProposal> _placeDetached(
    TxSession source, String symbol, TxSide side, TxKind kind,
    int quantity, int? limitPriceCents) {
  return Isolate.run(() => _placeOnWorker(
      source, symbol, side, kind, quantity, limitPriceCents));
}

Future<_TradeProposal> _cancelDetached(TxSession source, String orderId) {
  return Isolate.run(() => _cancelOnWorker(source, orderId));
}

Future<TxSession> _tickDetached(TxSession source) {
  return Isolate.run(() => _advanceMinute(source));
}

Future<TxSession> _pulseDetached(TxSession source, int second) {
  return Isolate.run(() => _advancePulse(source, second));
}

/// Actual stage durations, published only after a successfully acknowledged
/// SQLite minute. Never considered an achieved multiplier or FPS claim.
class TxTickTimings {
  const TxTickTimings({required this.market, required this.sqlite,
      required this.acknowledgement});
  final Duration market;
  final Duration sqlite;
  final Duration acknowledgement;
}

class TxTradingService {
  TxTradingService(this.database, {TxSession Function()? initialSessionFactory,
      this.persistentMarketWorker = false,
      this.nativeMarketWorker = false})
      : _initialSessionFactory = initialSessionFactory ?? TxSession.fresh;

  final TxSqliteStore database;
  final TxSession Function() _initialSessionFactory;
  /// Opt-in to a single long-lived isolate. Default retains original service
  /// semantics for older tests, embedders and in-memory database fixtures.
  final bool persistentMarketWorker;
  /// Production Android Rust-first matching; no Dart-only fallback.
  final bool nativeMarketWorker;
  TxPersistentMarketWorker? _worker;
  TxStoredSession? _current;
  bool _busy = false;
  bool _storageFault = false;
  TxTickTimings? _lastTickTimings;

  /// Null until the first complete, durably committed and acknowledged tick.
  /// On failure the previous sample is cleared rather than reported as new.
  TxTickTimings? get lastTickTimings => _lastTickTimings;

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
      final loaded = await database.readCurrent() ??
          await database.initializeFresh(_initialSessionFactory());
      if (persistentMarketWorker) {
        _worker = await TxPersistentMarketWorker.start(loaded.session,
            useNative: nativeMarketWorker);
      }
      _current = loaded;
      return loaded;
    } catch (_) {
      _storageFault = true;
      _worker?.close();
      _worker = null;
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
    _busy = true;
    try {
      if (_worker != null) {
        final proposal = await _worker!.place(
          symbol: symbol, side: side, kind: kind,
          quantity: quantity, limitPriceCents: limitPriceCents);
        await _commit(proposal.session);
        await _ackWorkerCommit();
        return current.session.engine.order(proposal.orderId!);
      }
      final source = current.session;
      final proposal = await _placeDetached(
          source, symbol, side, kind, quantity, limitPriceCents);
      await _commit(proposal.session);
      return current.session.engine.order(proposal.orderId);
    } catch (_) {
      // Invalid user orders must not poison an otherwise valid account.
      // Discard any uncommitted worker state and reinitialize from the exact
      // last committed revision. A genuine storage failure remains blocked.
      await _restoreWorkerAfterRejectedAction();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<TxOrder> cancel(String orderId) async {
    _ensureReady();
    _busy = true;
    try {
      if (_worker != null) {
        final proposal = await _worker!.cancel(orderId);
        await _commit(proposal.session);
        await _ackWorkerCommit();
        return current.session.engine.order(proposal.orderId!);
      }
      final source = current.session;
      final proposal = await _cancelDetached(source, orderId);
      await _commit(proposal.session);
      return current.session.engine.order(proposal.orderId);
    } catch (_) {
      await _restoreWorkerAfterRejectedAction();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<TxMinuteEventTape> nextTickWithTape() async {
    final before = current;
    final after = await nextTick();
    return TxMinuteEventTape.fromCommits(before, after);
  }

  /// Real Rust market pulse in the ongoing game minute. As with nextTick,
  /// nothing becomes visible until SQLite has committed and acknowledged it.
  Future<TxStoredSession> marketPulse(int second) async {
    _ensureReady();
    if (second < 5 || second >= 60) {
      throw ArgumentError.value(second, 'second');
    }
    if (second <= current.session.lastPulseSecond) return current;
    _busy = true;
    try {
      final candidate = _worker != null
          ? (await _worker!.pulse(second)).session
          : await _pulseDetached(current.session, second);
      await _commit(candidate);
      await _ackWorkerCommit();
      return current;
    } catch (_) {
      if (_worker != null) {
        _worker!.close();
        _worker = null;
      }
      _storageFault = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<TxStoredSession> nextTick() async {
    _ensureReady();
    _busy = true;
    _lastTickTimings = null;
    final clock = Stopwatch()..start();
    try {
      final candidate = _worker != null
          ? (await _worker!.tick()).session
          : await _tickDetached(current.session);
      final marketMicros = clock.elapsedMicroseconds;
      await _commit(candidate);
      final sqliteMicros = clock.elapsedMicroseconds - marketMicros;
      await _ackWorkerCommit();
      final ackMicros = clock.elapsedMicroseconds - marketMicros - sqliteMicros;
      _lastTickTimings = TxTickTimings(
        market: Duration(microseconds: marketMicros),
        sqlite: Duration(microseconds: sqliteMicros),
        acknowledgement: Duration(microseconds: ackMicros),
      );
      return current;
    } catch (_) {
      if (_worker != null) {
        _worker!.close();
        _worker = null;
        _storageFault = true;
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> _ackWorkerCommit() async {
    final worker = _worker;
    if (worker == null) return;
    try {
      await worker.acknowledgeCommitted();
    } catch (_) {
      // SQLite has already committed; recover the worker from the exact
      // committed UI mirror, never retry the trade or duplicate an order.
      worker.close();
      _worker = null;
      try {
        _worker = await TxPersistentMarketWorker.start(current.session,
            useNative: nativeMarketWorker);
      } catch (_) {
        _storageFault = true;
        rethrow;
      }
    }
  }

  Future<void> _restoreWorkerAfterRejectedAction() async {
    final stale = _worker;
    if (stale == null) return;
    stale.close();
    _worker = null;
    if (_storageFault) return;
    try {
      _worker = await TxPersistentMarketWorker.start(current.session,
            useNative: nativeMarketWorker);
    } catch (_) {
      _storageFault = true;
      rethrow;
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
    try {
      final saved = await database.saveSession(
        candidate, expectedRevision: current.revision,
      );
      _current = saved;
    } catch (_) {
      _storageFault = true;
      rethrow;
    }
  }

  Future<void> close() async {
    _worker?.close();
    _worker = null;
    await database.close();
  }
}
