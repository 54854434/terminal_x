/// Long-lived isolated market executor. Only candidates cross back to the UI;
/// the worker's authoritative working copy persists across successful minutes.
/// SQLite still owns final commit publication and revision validation.
import 'dart:async';
import 'dart:isolate';

import '../engine/tx_engine.dart';
import '../engine/tx_rust_market_gate.dart';
import '../engine/tx_session.dart';

class TxMarketProposal {
  const TxMarketProposal(this.session, this.orderId);
  final TxSession session;
  final String? orderId;
}

/// Worker never accesses SQLite. It returns an unpublished candidate which
/// the caller MUST atomically commit before updating its public current state.
class TxPersistentMarketWorker {
  TxPersistentMarketWorker._(this._isolate, this._commands);
  final Isolate _isolate;
  final SendPort _commands;
  bool _closed = false;

  static Future<TxPersistentMarketWorker> start(TxSession committed,
      {bool useNative = false}) async {
    final ready = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<List<dynamic>>(
        _runMarketWorker, <dynamic>[ready.sendPort, committed, useNative],
        errorsAreFatal: true,
        debugName: 'terminal_x_market_engine',
      );
      final port = await ready.first.timeout(const Duration(seconds: 15));
      if (port is! SendPort) {
        throw StateError('Market worker failed to start: $port');
      }
      return TxPersistentMarketWorker._(isolate, port);
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<TxMarketProposal> _request(String command, List<dynamic> args) async {
    if (_closed) throw StateError('Market worker is closed');
    final reply = ReceivePort();
    try {
      _commands.send(<dynamic>[command, args, reply.sendPort]);
      final result = await reply.first.timeout(const Duration(seconds: 30));
      if (result is! List || result.length != 3 || result[0] is! bool) {
        throw StateError('Invalid market worker reply');
      }
      if (result[0] != true) {
        if (result[1] == 'ArgumentError') {
          throw ArgumentError(result[2].toString());
        }
        throw StateError('Market worker rejected command: ${result[2]}');
      }
      if (result[1] is! TxSession ||
          (result[2] != null && result[2] is! String)) {
        throw StateError('Invalid market worker candidate');
      }
      return TxMarketProposal(result[1] as TxSession, result[2] as String?);
    } finally {
      reply.close();
    }
  }

  Future<TxMarketProposal> tick() => _request('tick', const <dynamic>[]);

  Future<TxMarketProposal> pulse(int second) =>
      _request('pulse', <dynamic>[second]);

  Future<TxMarketProposal> place({
    required String symbol,
    required TxSide side,
    required TxKind kind,
    required int quantity,
    int? limitPriceCents,
    TxTimeInForce timeInForce = TxTimeInForce.gtc,
  }) => _request('place', <dynamic>[symbol, side, kind, quantity,
      limitPriceCents, timeInForce]);

  Future<TxMarketProposal> cancel(String orderId) =>
      _request('cancel', <dynamic>[orderId]);

  /// The previously proposed revision has passed SQLite's atomic commit.
  /// Advances only the worker's volatile delta cursors; no snapshot roundtrip.
  Future<void> acknowledgeCommitted() async {
    if (_closed) throw StateError('Market worker is closed');
    final reply = ReceivePort();
    try {
      _commands.send(<dynamic>['ack', const <dynamic>[], reply.sendPort]);
      final result = await reply.first.timeout(const Duration(seconds: 30));
      if (result is! List || result.length != 3 || result[0] != true ||
          result[1] != 'ack') {
        throw StateError('Market worker commit acknowledgement failed');
      }
    } finally {
      reply.close();
    }
  }


  /// A failed proposal may have mutated the private worker state. Kill it;
  /// NEVER continue from that candidate or assume it was committed.
  void close() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _runMarketWorker(List<dynamic> launch) {
  final ready = launch[0] as SendPort;
  var working = launch[1] as TxSession;
  final useNative = launch[2] as bool;
  TxRustMarketGate? nativeGate;
  try {
    if (useNative) nativeGate = TxRustMarketGate.open(working);
  } catch (error) {
    ready.send('Rust native init failed: $error');
    return;
  }
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((dynamic request) {
    if (request is! List || request.length != 3) return;
    final reply = request[2] as SendPort;
    try {
      final command = request[0] as String;
      final args = request[1] as List;
      String? orderId;
      if (command == 'ack') {
        working.acknowledgeCommittedSnapshot();
        reply.send(<dynamic>[true, 'ack', null]);
        return;
      }
      if (command == 'tick') {
        working.nextTick();
      } else if (command == 'pulse') {
        working.marketPulse(args[0] as int);
      } else if (command == 'place') {
        final order = working.placePlayer(
          symbol: args[0] as String,
          side: args[1] as TxSide,
          kind: args[2] as TxKind,
          quantity: args[3] as int,
          limitPriceCents: args[4] as int?,
          timeInForce: args[5] as TxTimeInForce,
        );
        orderId = order.id;
      } else if (command == 'cancel') {
        final order = working.cancelPlayer(args[0] as String);
        orderId = order.id;
      } else {
        throw StateError('Unsupported market worker operation');
      }
      // The committed copy remains on the worker; isolate messaging creates
      // the separate candidate copied to the storage/UI isolate.
      reply.send(<dynamic>[true, working, orderId]);
    } catch (error) {
      reply.send(<dynamic>[
        false, error is ArgumentError ? 'ArgumentError' : 'StateError',
        error.toString(),
      ]);
      // A partial mutation must NEVER become the next candidate.
      commands.close();
      nativeGate?.close();
    }
  });
}
