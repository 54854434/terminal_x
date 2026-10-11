import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/engine/tx_backup_commit.dart';
import '../lib/engine/tx_engine.dart';
import '../lib/engine/tx_session.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('successful import archives V0.1c snapshot before replacement', () async {
    final current = TxSession.fresh();
    final prefs = await SharedPreferences.getInstance();
    expect(await prefs.setString(TxSession.saveKey, current.exportJson()), true);

    final legacyBackup = TxSession.fresh();
    legacyBackup.placePlayer(
      symbol: TxSession.symbols[0],
      side: TxSide.buy,
      kind: TxKind.market,
      quantity: 100,
    );
    final imported = await TxBackupCommit.commitOnce(legacyBackup);
    expect(imported.exportJson(), legacyBackup.exportJson());
    expect(prefs.getString(TxBackupCommit.preImportSaveKey),
        current.exportJson());
    expect(prefs.getString(TxSession.saveKey), legacyBackup.exportJson());
  });

  test('second import is refused without changing either snapshot', () async {
    final prefs = await SharedPreferences.getInstance();
    final prior = TxSession.fresh();
    await prefs.setString(TxSession.saveKey, prior.exportJson());
    final imported = TxSession.fresh()..nextTick();
    await TxBackupCommit.commitOnce(imported);
    final snapshot = prefs.getString(TxSession.saveKey);
    final archive = prefs.getString(TxBackupCommit.preImportSaveKey);
    await expectLater(
      () => TxBackupCommit.commitOnce(prior),
      throwsStateError,
    );
    expect(prefs.getString(TxSession.saveKey), snapshot);
    expect(prefs.getString(TxBackupCommit.preImportSaveKey), archive);
  });

  test('uninitialized target refuses import without creating any files', () async {
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
      () => TxBackupCommit.commitOnce(TxSession.fresh()),
      throwsStateError,
    );
    expect(prefs.containsKey(TxSession.saveKey), false);
    expect(prefs.containsKey(TxBackupCommit.preImportSaveKey), false);
  });

  test('corrupt current snapshot is never replaced or archived', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TxSession.saveKey, '{invalid');
    await expectLater(
      () => TxBackupCommit.commitOnce(TxSession.fresh()),
      throwsA(anything),
    );
    expect(prefs.getString(TxSession.saveKey), '{invalid');
    expect(prefs.containsKey(TxBackupCommit.preImportSaveKey), false);
  });
}
