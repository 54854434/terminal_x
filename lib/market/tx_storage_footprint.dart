/// Read-only summary of existing SQLite full-snapshot database.
/// Metrics represent physical DB pages and latest snapshot, not saved space.
class TxStorageFootprint {
  const TxStorageFootprint._({required this.pageCount,
    required this.pageSize, required this.snapshotCount,
    required this.latestSnapshotBytes, required this.revision});
  final int pageCount, pageSize, snapshotCount, latestSnapshotBytes, revision;
  static TxStorageFootprint fromRaw({required int pageCount,
    required int pageSize, required int snapshotCount,
    required int latestSnapshotBytes, required int revision}) {
    if (pageCount < 0 || pageSize < 1 || snapshotCount < 1 ||
        latestSnapshotBytes < 1 || revision < 1) {
      throw ArgumentError('Invalid SQLite diagnostic values');
    }
    return TxStorageFootprint._(pageCount: pageCount,
      pageSize: pageSize, snapshotCount: snapshotCount,
      latestSnapshotBytes: latestSnapshotBytes, revision: revision);
  }
  int get databaseBytes => pageCount * pageSize;
  double get databaseMiB => databaseBytes / 1048576;
  double get latestSnapshotKiB => latestSnapshotBytes / 1024;
  bool get largeDatabase => databaseBytes >= 100 * 1048576;
}
