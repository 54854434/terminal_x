/// V0.1d SQLite/Drift store. V0.1d uses initializeFresh() for a NEW account;
/// the legacy migration entry point remains optional and is never used by the
/// isolated SQLite trading application.
///
/// The caller supplies a full V0.1c JSON snapshot. This module never reads,
/// rewrites, or deletes SharedPreferences or the V0.1b XML backup.
///
/// Manual SQL is used for this initial schema to avoid generated-code churn.
/// Drift owns the SQLite connection, transactions and schema-version checks.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../engine/tx_session.dart';

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

/// [testCheckpoint] is exclusively for controlled rollback tests. It must not
/// be set by normal application code.
class TxSqliteStore extends GeneratedDatabase {
  TxSqliteStore(super.executor, {void Function(String)? testCheckpoint})
      : _testCheckpoint = testCheckpoint;

  static const String primarySessionId = 'primary';
  static const String migrationSource = 'v01c_shared_preferences';
  final void Function(String)? _testCheckpoint;

  @override
  int get schemaVersion => 1;

  // The initial schema is deliberately expressed in SQL below rather than in
  // generated TableInfo objects. It is not yet a normalized trading database.
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
          // Never drop or auto-recreate a database with existing user data.
          throw StateError('Unsupported SQLite schema upgrade $from -> $to');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  String _verifiedJson(String sourceJson) {
    final decoded = TxSession.importJson(sourceJson);
    decoded.engine.checkInvariants();
    // A fully validated canonical payload is what enters the database.
    return decoded.exportJson();
  }

  String _digest(String data) => sha256.convert(utf8.encode(data)).toString();

  String _utcNow() => DateTime.now().toUtc().toIso8601String();

  Future<int> _snapshotCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM snapshots',
    ).getSingle();
    return row.read<int>('n');
  }

  /// Reads only. Any invalid checksum, broken pointer, or invalid engine
  /// ledger throws; in particular, corruption NEVER creates a fresh account.
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
      // Orphan snapshots or migration records mean a damaged or unknown store,
      // not an invitation to initialize a new account.
      final archives = await _snapshotCount();
      final migrations = (await customSelect(
        'SELECT COUNT(*) AS n FROM migration_records',
      ).getSingle()).read<int>('n');
      if (archives != 0 || migrations != 0) {
        throw StateError('Orphaned SQLite data; refusing to initialize');
      }
      return null;
    }

    final activeRevision = row.read<int>('active_revision');
    final archivedRevision = row.read<int?>('snapshot_revision');
    final payload = row.read<String?>('payload_json');
    final storedHash = row.read<String?>('snapshot_hash');
    final snapshotSession = row.read<String?>('snapshot_session_id');
    if (activeRevision < 1 || archivedRevision != activeRevision ||
        snapshotSession != primarySessionId || payload == null ||
        storedHash == null || _digest(payload) != storedHash) {
      throw StateError('Corrupted SQLite session pointer or checksum');
    }

    final session = TxSession.importJson(payload);
    session.engine.checkInvariants();
    return TxStoredSession(
      session: session,
      revision: activeRevision,
      sha256: storedHash,
    );
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

  /// Explicit, once-only migration from a caller-provided SharedPreferences
  /// JSON string. Calling again with the SAME source returns the CURRENT
  /// revision without rewriting it. A different source is rejected.
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

  /// Atomic revisioned save. It cannot overwrite a concurrent/stale revision.
  /// Every save retains the prior snapshot for later audited recovery tooling.
  Future<TxStoredSession> saveSession(
    TxSession session, {
    required int expectedRevision,
  }) async {
    if (expectedRevision < 1) {
      throw ArgumentError.value(expectedRevision, 'expectedRevision');
    }
    // Capture and validate BEFORE beginning the SQLite transaction.
    final payload = _verifiedJson(session.exportJson());
    final checksum = _digest(payload);
    return transaction(() async {
      final old = await readCurrent();
      if (old == null) throw StateError('SQLite not migrated; save refused');
      if (old.revision != expectedRevision) {
        throw StateError('Stale revision; save refused');
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
      return (await readCurrent())!;
    });
  }

  /// Initializes a fresh account ONLY when the SQLite database is empty.
  /// Unlike legacy migration, no SharedPreferences migration marker is made.
  /// Existing valid sessions are returned untouched; corruption fails closed.
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


  /// Verified recent committed revisions, oldest first. Read-only.
  /// The chart uses ONLY persisted observations; historical corruption is
  /// reported and never silently replaced by fabricated OHLC candles.
  Future<List<TxStoredSession>> readHistory({int limit = 180}) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit');
    }
    final rows = await customSelect('''
      SELECT revision, payload_json, sha256
      FROM snapshots
      WHERE session_id = ?
      ORDER BY revision DESC LIMIT ?
    ''', variables: [
      Variable.withString(primarySessionId),
      Variable.withInt(limit),
    ]).get();
    final verified = <TxStoredSession>[];
    for (final row in rows.reversed) {
      final payload = row.read<String>('payload_json');
      final checksum = row.read<String>('sha256');
      if (_digest(payload) != checksum) {
        throw StateError('Corrupted historical SQLite snapshot');
      }
      final session = TxSession.importJson(payload);
      session.engine.checkInvariants();
      verified.add(TxStoredSession(
        session: session,
        revision: row.read<int>('revision'),
        sha256: checksum,
      ));
    }
    return verified;
  }
}
