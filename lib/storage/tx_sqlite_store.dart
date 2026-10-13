/// Revisioned, fail-closed SQLite session storage.
/// R27: bounded incremental revisions plus periodic full checkpoints.
/// Legacy plaintext and R26 compressed checkpoints are kept intact.
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../engine/tx_session.dart';
import '../market/tx_live_candles.dart';
import 'tx_delta_codec.dart';

// Candidate audit/encoding happens on a worker. The prior canonical snapshot
// and its hash are only accepted if the SQL transaction later verifies the
// exact same on-disk revision. Never publish an uncommitted candidate.
class _PreparedSnapshot {
  const _PreparedSnapshot(this.session, this.stored, this.digest,
      this.canonical);
  final TxSession session;
  final String stored;
  final String digest;
  final String canonical;
}

_PreparedSnapshot _prepareSnapshot(
    TxSession proposed, String? previousCanonical, int previousRevision,
    String? previousHash, int checkpointInterval) {
  // Capture the worker's dirty-record journal BEFORE canonical import resets
  // the in-memory hints. Canonical import itself already performs the full
  // engine invariant audit: don't repeat that costly ledger scan here.
  final trackedLists = proposed.engine.snapshotDeltaLists();
  final trackedSessionHeader = trackedLists == null
      ? null : proposed.snapshotHeader();
  final trackedEngineHeader = trackedLists == null
      ? null : proposed.engine.snapshotHeader();
  // The source is a typed, unpublished isolate candidate. One complete
  // release-mode invariant audit is sufficient; re-importing its full JSON
  // would audit and materialize the same ever-growing history again.
  proposed.checkInvariantsForCommit();
  final checked = proposed;
  final canonical = proposed.exportJson();
  final encoded = TxDeltaCodec.encode(
    canonical: canonical,
    revision: previousRevision + 1,
    previousRevision: previousRevision,
    previousCanonical: previousCanonical,
    previousHash: previousHash,
    checkpointInterval: checkpointInterval,
    trackedSessionHeader: trackedSessionHeader,
    trackedEngineHeader: trackedEngineHeader,
    trackedLists: trackedLists,
  );
  if (!encoded.checkpoint) {
    // Verify the delta reconstructs the EXACT validated canonical candidate.
    // Prevent committing any patch with subtly different field or list order.
    final rebuilt = TxDeltaCodec.replay(
      previousCanonical: previousCanonical!,
      previousRevision: previousRevision,
      previousHash: previousHash!,
      stored: encoded.stored,
    );
    if (rebuilt != canonical) {
      throw StateError('Incremental snapshot roundtrip mismatch');
    }
  }
  // The candidate is sent back as a committed session only if the SQL
  // transaction succeeds; resetting its volatile journal has no effect on
  // the full canonical payload or account balances.
  checked.acknowledgeCommittedSnapshot();
  return _PreparedSnapshot(checked, encoded.stored, encoded.sha256, canonical);
}

// Keep Isolate.run's closure OUTSIDE the database instance method.
// Dart may capture the enclosing `this` even when the closure only seems to
// use local variables, which would try to send Drift/sqlite3 FFI handles.
// This top-level runner closes over sendable DTOs only.
Future<_PreparedSnapshot> _prepareSnapshotOffThread(
    TxSession session, String? cachedCanonical, int expectedRevision,
    String? cachedHash, int checkpointInterval) {
  return Isolate.run(() => _prepareSnapshot(
      session, cachedCanonical, expectedRevision,
      cachedHash, checkpointInterval));
}

class TxStoredSession {
  const TxStoredSession({
    required this.session,
    required this.revision,
    required this.sha256,
  });
  final TxSession session;
  final int revision;
  final String sha256;
}

class TxSqliteStore extends GeneratedDatabase {
  TxSqliteStore(super.executor, {void Function(String)? testCheckpoint})
      : _testCheckpoint = testCheckpoint;

  static const String primarySessionId = 'primary';
  static const String migrationSource = 'v01c_shared_preferences';
  static const String _checkpointPolicyKey = 'checkpoint_interval';
  static const String _candleIndexKey = 'candle_index_v1';
  TxLiveCandles? _indexedCandles;
  int? _indexedRevision;
  TxStoredSession? _cachedCurrent;
  final void Function(String)? _testCheckpoint;

  // Only a successful audited read or a committed, validated write may
  // advance this cache. It is never persisted or accepted as a substitute
  // for the actual SQLite checksum and revision checks.
  int? _verifiedRevision;
  String? _verifiedHash;
  // In-memory only. Rebuilt with bounded, hash-chained replay on every open.
  // This never overrides the committed SQLite head or revision CAS guard.
  String? _headCanonical;

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities =>
      const <DatabaseSchemaEntity>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE snapshots (
              snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              revision INTEGER NOT NULL CHECK (revision >= 1),
              payload_json TEXT NOT NULL,
              sha256 TEXT NOT NULL,
              saved_at_utc TEXT NOT NULL,
              UNIQUE(session_id, revision)
            )
          ''');
          await customStatement('''
            CREATE TABLE sessions (
              session_id TEXT PRIMARY KEY,
              revision INTEGER NOT NULL CHECK (revision >= 1),
              snapshot_id INTEGER NOT NULL REFERENCES snapshots(snapshot_id),
              updated_at_utc TEXT NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE migration_records (
              source_key TEXT PRIMARY KEY,
              content_sha256 TEXT NOT NULL,
              snapshot_id INTEGER NOT NULL REFERENCES snapshots(snapshot_id),
              completed_at_utc TEXT NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE storage_metadata (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await customStatement(
            "INSERT INTO storage_metadata(key, value) VALUES ('schema_kind', 'full_snapshot_v1')",
          );
        },
        onUpgrade: (m, from, to) async {
          throw StateError('Unsupported SQLite schema upgrade $from -> $to');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  String _verifiedJson(String sourceJson) {
    // Import itself audits every account, order, fill and ledger line.
    return TxSession.importJson(sourceJson).exportJson();
  }

  String _digest(String data) => sha256.convert(utf8.encode(data)).toString();

  String _utcNow() => DateTime.now().toUtc().toIso8601String();

  /// This preference is saved in the existing schema-1 metadata table.
  /// A missing value means R27's original 32-revision behavior. It never
  /// controls whether an actual trade/minute is durably committed.
  Future<int> readCheckpointInterval() async {
    final row = await customSelect('''
      SELECT value FROM storage_metadata WHERE key = ?
    ''', variables: [Variable.withString(_checkpointPolicyKey)])
        .getSingleOrNull();
    if (row == null) return TxDeltaCodec.checkpointInterval;
    final value = int.tryParse(row.read<String>('value'));
    if (value == null || !TxDeltaCodec.validCheckpointInterval(value)) {
      throw StateError('Invalid stored SQLite checkpoint interval');
    }
    return value;
  }

  /// Update only a storage policy, never the account state or revision.
  /// The next complete snapshot is determined by the updated interval.
  Future<void> setCheckpointInterval(int value) async {
    if (!TxDeltaCodec.validCheckpointInterval(value)) {
      throw ArgumentError.value(value, 'checkpointInterval');
    }
    await transaction(() async {
      final head = await customSelect('''
        SELECT revision FROM sessions WHERE session_id = ?
      ''', variables: [Variable.withString(primarySessionId)])
          .getSingleOrNull();
      if (head == null) {
        throw StateError('SQLite session must be initialized before setting cadence');
      }
      await customStatement('''
        INSERT INTO storage_metadata(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''', <Object?>[_checkpointPolicyKey, value.toString()]);
    });
  }

  /// Non-authoritative, bounded OHLC read model. Corrupt/stale records are
  /// rejected so callers can fall back to fully verified historical snapshots.
  /// No account, fill, order or cash balance is ever restored from this cache.
  Future<TxLiveCandles?> readCandleIndex(TxStoredSession committed) async {
    final row = await customSelect('''
      SELECT value FROM storage_metadata WHERE key = ?
    ''', variables: [Variable.withString(_candleIndexKey)])
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final envelope = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('value')) as Map);
      if (envelope.length != 5 || envelope['version'] != 1 ||
          envelope['revision'] != committed.revision ||
          envelope['headSha256'] != committed.sha256) return null;
      final serialized = envelope['data'] as String;
      final hash = envelope['dataSha256'] as String?;
      if (hash == null || _digest(serialized) != hash) return null;
      final parsed = Map<String, dynamic>.from(
          jsonDecode(serialized) as Map);
      final recovered = TxLiveCandles.fromIndexJson(parsed);
      // Reconcile the latest plotted observation with the already-audited
      // authoritative account; display cache never supplies executable quotes.
      for (final symbol in TxSession.symbols) {
        final series = recovered.forSymbol(symbol);
        if (series.isEmpty || series.last.step != committed.session.step ||
            series.last.closeCents != committed.session.lastPrice(symbol)) {
          return null;
        }
      }
      _indexedCandles = recovered;
      _indexedRevision = committed.revision;
      _cachedCurrent = committed;
      return recovered;
    } catch (_) {
      return null;
    }
  }

  String _encodeCandleIndex(TxLiveCandles candles,
      int revision, String headHash) {
    final serialized = jsonEncode(candles.toIndexJson());
    return jsonEncode(<String, dynamic>{
      'version': 1, 'revision': revision, 'headSha256': headHash,
      'data': serialized, 'dataSha256': _digest(serialized),
    });
  }

  /// Seed the index once from a verified legacy history, if no current index
  /// exists. The revision guard makes racing trades safe; never overwrite a
  /// newer cache, and never change the economic/session revision.
  Future<void> seedCandleIndex(
      TxStoredSession committed, TxLiveCandles candles) async {
    if (_indexedRevision == committed.revision) return;
    for (final symbol in TxSession.symbols) {
      final series = candles.forSymbol(symbol);
      if (series.isEmpty || series.last.step != committed.session.step ||
          series.last.closeCents != committed.session.lastPrice(symbol)) {
        throw StateError('Cannot index unverified candle state');
      }
    }
    final encoded = _encodeCandleIndex(
        candles, committed.revision, committed.sha256);
    await transaction(() async {
      await _verifyPreviousHead(committed.revision);
      await customStatement('''
        INSERT INTO storage_metadata(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''', <Object?>[_candleIndexKey, encoded]);
    });
    _indexedCandles = candles;
    _indexedRevision = committed.revision;
    _cachedCurrent = committed;
  }

  Future<int> _snapshotCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM snapshots',
    ).getSingle();
    return row.read<int>('n');
  }

  // Rebuild at most 63 deltas from the nearest complete checkpoint. All
  // storage hashes are checked before decoding or applying any patch.
  // TXZ1 and schema-1 plaintext are both complete checkpoints.
  Future<String> _readCanonicalAt(int revision) async {
    if (revision < 1) throw StateError('Invalid SQLite revision');
    final rows = await customSelect('''
      SELECT revision, payload_json, sha256 FROM snapshots
      WHERE session_id = ? AND revision <= ?
      ORDER BY revision DESC LIMIT ?
    ''', variables: [
      Variable.withString(primarySessionId),
      Variable.withInt(revision),
      Variable.withInt(TxDeltaCodec.maxCheckpointInterval + 1),
    ]).get();
    if (rows.isEmpty || rows.first.read<int>('revision') != revision) {
      throw StateError('Missing SQLite revision');
    }
    final ordered = rows.reversed.toList();
    var checkpoint = -1;
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (!TxDeltaCodec.isDelta(ordered[i].read<String>('payload_json'))) {
        checkpoint = i;
        break;
      }
    }
    if (checkpoint < 0) throw StateError('Missing SQLite delta checkpoint');
    String? canonical;
    String? priorHash;
    int? priorRevision;
    for (var i = checkpoint; i < ordered.length; i++) {
      final row = ordered[i];
      final at = row.read<int>('revision');
      final payload = row.read<String>('payload_json');
      final hash = row.read<String>('sha256');
      if (TxDeltaCodec.checksum(payload) != hash) {
        throw StateError('Corrupted historical SQLite checksum');
      }
      if (canonical != null && at != priorRevision! + 1) {
        throw StateError('Gap in SQLite delta history');
      }
      if (TxDeltaCodec.isDelta(payload)) {
        if (canonical == null || priorHash == null || priorRevision == null) {
          throw StateError('Missing SQLite delta base');
        }
        canonical = TxDeltaCodec.replay(
          previousCanonical: canonical,
          previousRevision: priorRevision,
          previousHash: priorHash,
          stored: payload,
        );
      } else {
        canonical = TxDeltaCodec.decodeFull(payload);
      }
      priorRevision = at;
      priorHash = hash;
    }
    return canonical!;
  }

  /// Full audit on every open; damaged or incomplete delta chains fail closed.
  Future<TxStoredSession?> readCurrent() async {
    final row = await customSelect('''
      SELECT s.revision AS active_revision,
             h.revision AS snapshot_revision,
             h.payload_json AS payload_json,
             h.sha256 AS snapshot_hash,
             h.session_id AS snapshot_session_id
      FROM sessions s
      LEFT JOIN snapshots h ON h.snapshot_id = s.snapshot_id
      WHERE s.session_id = ?
    ''', variables: [Variable.withString(primarySessionId)]).getSingleOrNull();

    if (row == null) {
      final archives = await _snapshotCount();
      final migrations = (await customSelect(
        'SELECT COUNT(*) AS n FROM migration_records',
      ).getSingle()).read<int>('n');
      if (archives != 0 || migrations != 0) {
        throw StateError('Orphaned SQLite data; refusing to initialize');
      }
      _verifiedRevision = null;
      _verifiedHash = null;
      _headCanonical = null;
      return null;
    }
    final activeRevision = row.read<int>('active_revision');
    final archivedRevision = row.read<int?>('snapshot_revision');
    final payload = row.read<String?>('payload_json');
    final storedHash = row.read<String?>('snapshot_hash');
    final snapshotSession = row.read<String?>('snapshot_session_id');
    if (activeRevision < 1 || archivedRevision != activeRevision ||
        snapshotSession != primarySessionId || payload == null ||
        storedHash == null || TxDeltaCodec.checksum(payload) != storedHash) {
      throw StateError('Corrupted SQLite session pointer or checksum');
    }
    final canonical = await _readCanonicalAt(activeRevision);
    final session = TxSession.importJson(canonical);
    // TxSession.importJson already enforces TxEngine.checkInvariants().
    _verifiedRevision = activeRevision;
    _verifiedHash = storedHash;
    _headCanonical = canonical;
    final committed = TxStoredSession(
      session: session,
      revision: activeRevision,
      sha256: storedHash,
    );
    _cachedCurrent = committed;
    return committed;
  }

  Future<int> _insertSnapshot(
    String payload,
    String checksum,
    int revision,
    String timestamp,
  ) async {
    await customStatement('''
      INSERT INTO snapshots(session_id, revision, payload_json, sha256, saved_at_utc)
      VALUES (?, ?, ?, ?, ?)
    ''', [primarySessionId, revision, payload, checksum, timestamp]);

    final row = await customSelect('''
      SELECT snapshot_id FROM snapshots
      WHERE session_id = ? AND revision = ?
    ''', variables: [
      Variable.withString(primarySessionId),
      Variable.withInt(revision),
    ]).getSingle();
    return row.read<int>('snapshot_id');
  }

  /// Verify the disk head inside the write transaction. A snapshot with a
  /// broken checksum or pointer is never overwritten. If it has already
  /// passed a full ledger audit in this process, skip parsing the entire
  /// growing order/ledger history a second time; otherwise audit it once.
  Future<void> _verifyPreviousHead(int expectedRevision) async {
    final row = await customSelect('''
      SELECT s.revision AS active_revision,
             h.revision AS snapshot_revision,
             h.session_id AS snapshot_session_id,
             h.payload_json AS payload_json,
             h.sha256 AS snapshot_hash
      FROM sessions s
      LEFT JOIN snapshots h ON h.snapshot_id = s.snapshot_id
      WHERE s.session_id = ?
    ''', variables: [Variable.withString(primarySessionId)]).getSingleOrNull();
    if (row == null) throw StateError('SQLite not migrated; save refused');
    final active = row.read<int>('active_revision');
    if (active != expectedRevision) {
      throw StateError('Stale revision; save refused');
    }
    final stored = row.read<int?>('snapshot_revision');
    final source = row.read<String?>('snapshot_session_id');
    final data = row.read<String?>('payload_json');
    final oldHash = row.read<String?>('snapshot_hash');
    if (stored != active || source != primarySessionId ||
        data == null || oldHash == null || _digest(data) != oldHash) {
      throw StateError('Corrupted SQLite session pointer or checksum');
    }
    if (_verifiedRevision == active && _verifiedHash != oldHash) {
      throw StateError('SQLite snapshot unexpectedly changed since audit');
    }
    if (_verifiedRevision != active || _verifiedHash != oldHash) {
      final canonical = await _readCanonicalAt(active);
      // Import performs the full ledger audit exactly once.
      TxSession.importJson(canonical);
      _headCanonical = canonical;
    }
  }

  /// Explicit once-only migration from a provided SharedPreferences snapshot.
  Future<TxStoredSession> migrateFromPreferencesSnapshot(String sourceJson) async {
    final payload = _verifiedJson(sourceJson);
    final checksum = _digest(payload);
    return transaction(() async {
      final migrationRow = await customSelect('''
        SELECT content_sha256, snapshot_id FROM migration_records
        WHERE source_key = ?
      ''', variables: [Variable.withString(migrationSource)]).getSingleOrNull();

      if (migrationRow != null) {
        if (migrationRow.read<String>('content_sha256') != checksum) {
          throw StateError('A different source snapshot was already migrated');
        }
        final sourceSnapshot = await customSelect('''
          SELECT sha256, payload_json FROM snapshots WHERE snapshot_id = ?
        ''', variables: [
          Variable.withInt(migrationRow.read<int>('snapshot_id')),
        ]).getSingleOrNull();
        if (sourceSnapshot == null ||
            sourceSnapshot.read<String>('sha256') != checksum ||
            _digest(sourceSnapshot.read<String>('payload_json')) != checksum) {
          throw StateError('The original migrated snapshot is corrupted');
        }
        final current = await readCurrent();
        if (current == null) {
          throw StateError('Migration marker exists without a live session');
        }
        return current;
      }

      if (await readCurrent() != null || await _snapshotCount() != 0) {
        throw StateError('SQLite already contains data; migration is blocked');
      }
      final now = _utcNow();
      final id = await _insertSnapshot(payload, checksum, 1, now);
      _testCheckpoint?.call('after_snapshot_insert');
      await customStatement('''
        INSERT INTO sessions(session_id, revision, snapshot_id, updated_at_utc)
        VALUES (?, ?, ?, ?)
      ''', [primarySessionId, 1, id, now]);
      _testCheckpoint?.call('after_session_insert');
      await customStatement('''
        INSERT INTO migration_records(
          source_key, content_sha256, snapshot_id, completed_at_utc
        ) VALUES (?, ?, ?, ?)
      ''', [migrationSource, checksum, id, now]);
      _testCheckpoint?.call('before_transaction_commit');
      return (await readCurrent())!;
    });
  }

  /// Atomic revisioned save. New candidate receives one full validation;
  /// previous disk head receives a checksum and revision guard, without a
  /// redundant full audit when it is the already-trusted committed revision.
  Future<TxStoredSession> saveSession(
    TxSession session, {
    required int expectedRevision,
  }) async {
    if (expectedRevision < 1) {
      throw ArgumentError.value(expectedRevision, 'expectedRevision');
    }
    // The full JSON audit, SHA-256 and zlib encoding run outside Flutter's
    // UI isolate. SQLite pointer updates remain on the same serialized
    // database connection and retain the original transactional semantics.
    final cachedCanonical = _verifiedRevision == expectedRevision
        ? _headCanonical : null;
    final cachedHash = _verifiedRevision == expectedRevision
        ? _verifiedHash : null;
    final interval = await readCheckpointInterval();
    final prepared = await _prepareSnapshotOffThread(
        session, cachedCanonical, expectedRevision, cachedHash, interval);
    final checked = prepared.session;
    final payload = prepared.stored;
    final checksum = prepared.digest;

    // Prepare the bounded chart read model without touching the committed
    // copy. Publish it only after the SQLite snapshot transaction succeeds.
    TxLiveCandles? nextCandles;
    String? nextIndexJson;
    if (_indexedRevision == expectedRevision &&
        _indexedCandles != null && _cachedCurrent != null) {
      nextCandles = TxLiveCandles.fromIndexJson(
          _indexedCandles!.toIndexJson());
      nextCandles.addCommit(_cachedCurrent!, TxStoredSession(
        session: checked, revision: expectedRevision + 1, sha256: checksum));
      nextIndexJson = _encodeCandleIndex(
          nextCandles, expectedRevision + 1, checksum);
    }

    final committed = await transaction(() async {
      await _verifyPreviousHead(expectedRevision);
      // Prevent an external policy update during worker encoding from
      // silently committing a snapshot against an obsolete cadence.
      if (await readCheckpointInterval() != interval) {
        throw StateError('SQLite checkpoint policy changed during save');
      }
      final revision = expectedRevision + 1;
      final now = _utcNow();
      final id = await _insertSnapshot(payload, checksum, revision, now);
      _testCheckpoint?.call('after_snapshot_insert');
      final updated = await customUpdate('''
        UPDATE sessions SET revision = ?, snapshot_id = ?, updated_at_utc = ?
        WHERE session_id = ? AND revision = ?
      ''', variables: [
        Variable.withInt(revision),
        Variable.withInt(id),
        Variable.withString(now),
        Variable.withString(primarySessionId),
        Variable.withInt(expectedRevision),
      ]);
      if (updated != 1) throw StateError('Concurrent revision change');
      _testCheckpoint?.call('after_session_insert');
      if (nextIndexJson != null) {
        await customStatement('''
          INSERT INTO storage_metadata(key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
        ''', <Object?>[_candleIndexKey, nextIndexJson]);
      }
      return TxStoredSession(
        session: checked, revision: revision, sha256: checksum);
    });
    // Update cache ONLY after the transaction has committed. A failed write
    // must leave the previous audited head trusted and available for retry.
    _verifiedRevision = committed.revision;
    _verifiedHash = committed.sha256;
    _headCanonical = prepared.canonical;
    _cachedCurrent = committed;
    if (nextCandles != null) {
      _indexedCandles = nextCandles;
      _indexedRevision = committed.revision;
    }
    return committed;
  }

  Future<TxStoredSession> initializeFresh(TxSession initialSession) async {
    final payload = _verifiedJson(initialSession.exportJson());
    final checksum = _digest(payload);
    return transaction(() async {
      final existing = await readCurrent();
      if (existing != null) return existing;
      final now = _utcNow();
      final snapshotId = await _insertSnapshot(payload, checksum, 1, now);
      _testCheckpoint?.call('after_snapshot_insert');
      await customStatement('''
        INSERT INTO sessions(session_id, revision, snapshot_id, updated_at_utc)
        VALUES (?, ?, ?, ?)
      ''', [primarySessionId, 1, snapshotId, now]);
      _testCheckpoint?.call('after_session_insert');
      return (await readCurrent())!;
    });
  }

  /// Replays a single contiguous window from the checkpoint preceding the
  /// oldest requested revision. No N-by-N repeated checkpoint decoding.
  Future<List<TxStoredSession>> readHistory({int limit = 180}) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit');
    }
    final rows = await customSelect('''
      SELECT revision, payload_json, sha256 FROM snapshots
      WHERE session_id = ?
      ORDER BY revision DESC LIMIT ?
    ''', variables: [
      Variable.withString(primarySessionId),
      Variable.withInt(limit + TxDeltaCodec.maxCheckpointInterval),
    ]).get();
    if (rows.isEmpty) return <TxStoredSession>[];
    final ordered = rows.reversed.toList();
    final targetIndex = ordered.length > limit ? ordered.length - limit : 0;
    var checkpoint = -1;
    for (var i = targetIndex; i >= 0; i--) {
      if (!TxDeltaCodec.isDelta(ordered[i].read<String>('payload_json'))) {
        checkpoint = i;
        break;
      }
    }
    if (checkpoint < 0) throw StateError('Missing historical checkpoint');
    final verified = <TxStoredSession>[];
    String? canonical;
    String? previousHash;
    int? previousRevision;
    for (var i = checkpoint; i < ordered.length; i++) {
      final row = ordered[i];
      final revision = row.read<int>('revision');
      final stored = row.read<String>('payload_json');
      final hash = row.read<String>('sha256');
      if (TxDeltaCodec.checksum(stored) != hash) {
        throw StateError('Corrupted historical SQLite checksum');
      }
      if (previousRevision != null && revision != previousRevision + 1) {
        throw StateError('Missing historical SQLite revision');
      }
      if (TxDeltaCodec.isDelta(stored)) {
        if (canonical == null || previousHash == null ||
            previousRevision == null) {
          throw StateError('Missing historical delta base');
        }
        canonical = TxDeltaCodec.replay(
          previousCanonical: canonical,
          previousRevision: previousRevision,
          previousHash: previousHash,
          stored: stored,
        );
      } else {
        canonical = TxDeltaCodec.decodeFull(stored);
      }
      if (i >= targetIndex) {
        // TxEngine.importJson already performs the complete ledger audit.
        final session = TxSession.importJson(canonical!);
        verified.add(TxStoredSession(
          session: session, revision: revision, sha256: hash));
      }
      previousRevision = revision;
      previousHash = hash;
    }
    return verified;
  }
}
