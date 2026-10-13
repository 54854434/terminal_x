/// R27 versioned, checksummed, bounded replay for schema-1 SQLite snapshots.
/// This is not an execution or trading format. Every reconstructed session is
/// audited by TxSession.importJson before being exposed to the application.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class TxEncodedSnapshot {
  const TxEncodedSnapshot(this.stored, this.sha256, this.checkpoint);
  final String stored;
  final String sha256;
  final bool checkpoint;
}

class TxDeltaCodec {
  const TxDeltaCodec._();

  static const String fullPrefix = 'TXZ1:';
  static const String deltaPrefix = 'TXD1:';
  /// Default saved cadence; older R27 databases use this if no preference exists.
  static const int checkpointInterval = 32;
  /// Global hard recovery bound, regardless of changes to the user cadence.
  static const int maxCheckpointInterval = 64;

  static bool validCheckpointInterval(int value) =>
      value >= 1 && value <= maxCheckpointInterval;
  static const _lists = <String>['accounts', 'orders', 'fills', 'ledger'];

  static bool isDelta(String stored) => stored.startsWith(deltaPrefix);

  static String checksum(String stored) =>
      sha256.convert(utf8.encode(stored)).toString();

  static String _compress(String prefix, String value) =>
      '$prefix${base64Encode(ZLibCodec(level: 1).encode(utf8.encode(value)))}';

  static String _decompress(String value, String prefix) {
    try {
      return utf8.decode(ZLibCodec().decode(
        base64Decode(value.substring(prefix.length)),
      ));
    } catch (_) {
      throw StateError('Corrupted $prefix SQLite snapshot');
    }
  }

  static String decodeFull(String stored) {
    if (isDelta(stored)) {
      throw StateError('Delta snapshot requires its preceding revision');
    }
    if (stored.startsWith(fullPrefix)) return _decompress(stored, fullPrefix);
    if (!stored.startsWith('{')) {
      throw StateError('Unknown SQLite snapshot encoding');
    }
    return stored; // Older schema-1 snapshots contain canonical plaintext JSON.
  }

  static TxEncodedSnapshot encode({
    required String canonical,
    required int revision,
    required int previousRevision,
    required String? previousCanonical,
    required String? previousHash,
    int checkpointInterval = TxDeltaCodec.checkpointInterval,
    Map<String, dynamic>? trackedSessionHeader,
    Map<String, dynamic>? trackedEngineHeader,
    Map<String, dynamic>? trackedLists,
  }) {
    if (!validCheckpointInterval(checkpointInterval)) {
      throw ArgumentError.value(checkpointInterval, 'checkpointInterval');
    }
    if (revision < 2 || previousRevision + 1 != revision) {
      throw StateError('Noncontiguous storage revision');
    }
    // User-selected cadence writes full snapshots more/less frequently.
    // A universal 64-revision checkpoint prevents an unbounded replay chain
    // when the user changes cadence in the middle of an existing chain.
    if (previousCanonical == null || previousHash == null ||
        revision % checkpointInterval == 0 ||
        revision % maxCheckpointInterval == 0) {
      final stored = _compress(fullPrefix, canonical);
      return TxEncodedSnapshot(stored, checksum(stored), true);
    }
    // A trusted engine can supply dirty account/order indexes and append-only
    // fill/ledger cursors. This avoids per-record JSON comparisons across an
    // ever-growing history. Full replay-equivalence is enforced by the caller.
    final tracked = trackedSessionHeader != null &&
        trackedEngineHeader != null && trackedLists != null;
    if (tracked) {
      final patch = jsonEncode(<String, dynamic>{
        'version': 1,
        'baseRevision': previousRevision,
        'baseSha256': previousHash,
        'session': trackedSessionHeader,
        'engine': trackedEngineHeader,
        'lists': trackedLists,
      });
      if (patch.length * 5 >= canonical.length * 4) {
        final stored = _compress(fullPrefix, canonical);
        return TxEncodedSnapshot(stored, checksum(stored), true);
      }
      final stored = _compress(deltaPrefix, patch);
      return TxEncodedSnapshot(stored, checksum(stored), false);
    }
    final oldSession = Map<String, dynamic>.from(jsonDecode(previousCanonical) as Map);
    final nextSession = Map<String, dynamic>.from(jsonDecode(canonical) as Map);
    final oldEngine = Map<String, dynamic>.from(
        jsonDecode(oldSession['engine'] as String) as Map);
    final newEngine = Map<String, dynamic>.from(
        jsonDecode(nextSession['engine'] as String) as Map);
    final changes = <String, dynamic>{};
    for (final key in _lists) {
      final before = List<dynamic>.from(oldEngine[key] as List);
      final after = List<dynamic>.from(newEngine[key] as List);
      if (after.length < before.length) {
        final stored = _compress(fullPrefix, canonical);
        return TxEncodedSnapshot(stored, checksum(stored), true);
      }
      final updates = <List<dynamic>>[];
      for (var i = 0; i < before.length; i++) {
        if (jsonEncode(before[i]) != jsonEncode(after[i])) {
          updates.add(<dynamic>[i, after[i]]);
        }
      }
      changes[key] = <String, dynamic>{
        'oldLength': before.length,
        'updates': updates,
        'append': after.sublist(before.length),
      };
    }
    final header = Map<String, dynamic>.from(nextSession)..remove('engine');
    final engineHeader = Map<String, dynamic>.from(newEngine);
    for (final key in _lists) {
      engineHeader.remove(key);
    }
    final patch = jsonEncode(<String, dynamic>{
      'version': 1,
      'baseRevision': previousRevision,
      'baseSha256': previousHash,
      'session': header,
      'engine': engineHeader,
      'lists': changes,
    });
    // Delta larger than a reasonable fraction of the full snapshot is a
    // poor trade: checkpoint early rather than storing an inefficient delta.
    if (patch.length * 5 >= canonical.length * 4) {
      final stored = _compress(fullPrefix, canonical);
      return TxEncodedSnapshot(stored, checksum(stored), true);
    }
    final stored = _compress(deltaPrefix, patch);
    return TxEncodedSnapshot(stored, checksum(stored), false);
  }

  /// Apply only after the caller checks *both* stored SHA-256 values.
  static String replay({
    required String previousCanonical,
    required int previousRevision,
    required String previousHash,
    required String stored,
  }) {
    if (!isDelta(stored)) throw StateError('Expected TXD1 delta');
    final patch = Map<String, dynamic>.from(
        jsonDecode(_decompress(stored, deltaPrefix)) as Map);
    if (patch['version'] != 1 ||
        patch['baseRevision'] != previousRevision ||
        patch['baseSha256'] != previousHash) {
      throw StateError('Broken SQLite revision delta chain');
    }
    final session = Map<String, dynamic>.from(
        jsonDecode(previousCanonical) as Map);
    final engine = Map<String, dynamic>.from(
        jsonDecode(session['engine'] as String) as Map);
    final sessionHeader = Map<String, dynamic>.from(patch['session'] as Map);
    final engineHeader = Map<String, dynamic>.from(patch['engine'] as Map);
    final changes = Map<String, dynamic>.from(patch['lists'] as Map);
    if (sessionHeader.containsKey('engine') ||
        _lists.any((key) => engineHeader.containsKey(key)) ||
        changes.length != _lists.length ||
        sessionHeader.length != session.length - 1 ||
        engineHeader.length != engine.length - _lists.length ||
        sessionHeader.keys.any((k) => !session.containsKey(k)) ||
        engineHeader.keys.any((k) => !engine.containsKey(k))) {
      throw StateError('Invalid SQLite incremental snapshot schema');
    }
    for (final key in sessionHeader.keys) {
      session[key] = sessionHeader[key];
    }
    for (final key in engineHeader.keys) {
      engine[key] = engineHeader[key];
    }
    for (final key in _lists) {
      final spec = Map<String, dynamic>.from(changes[key] as Map);
      if (spec.length != 3 || !spec.containsKey('oldLength') ||
          !spec.containsKey('updates') || !spec.containsKey('append')) {
        throw StateError('Malformed SQLite delta list');
      }
      final list = List<dynamic>.from(engine[key] as List);
      if (spec['oldLength'] != list.length) {
        throw StateError('SQLite delta list base length mismatch');
      }
      final modified = <int>{};
      for (final record in (spec['updates'] as List)) {
        final pair = List<dynamic>.from(record as List);
        if (pair.length != 2 || pair[0] is! int ||
            (pair[0] as int) < 0 || (pair[0] as int) >= list.length ||
            !modified.add(pair[0] as int)) {
          throw StateError('Invalid SQLite delta replacement');
        }
        list[pair[0] as int] = pair[1];
      }
      list.addAll(spec['append'] as List);
      engine[key] = list;
    }
    session['engine'] = jsonEncode(engine);
    return jsonEncode(session);
  }
}
