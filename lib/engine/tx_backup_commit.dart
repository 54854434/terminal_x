/// V0.1c one-time backup import commit. The legacy app is a DIFFERENT Android
/// application ID; this code touches ONLY V0.1c's own SharedPreferences.
///
/// Before changing the current V0.1c session, preserve its existing validated
/// snapshot under a separate key. A failed or repeated import fails closed.
import 'package:shared_preferences/shared_preferences.dart';

import 'tx_session.dart';

class TxBackupCommit {
  static const preImportSaveKey = 'terminal_x_v01c_pre_import_state';

  static Future<TxSession> commitOnce(TxSession preview) async {
    // Revalidate the preview before making ANY local storage changes.
    final replacementJson = preview.exportJson();
    final replacement = TxSession.importJson(replacementJson);
    replacement.engine.checkInvariants();

    final prefs = await SharedPreferences.getInstance();
    final previousJson = prefs.getString(TxSession.saveKey);
    if (previousJson == null) {
      throw StateError('Current V0.1c session not initialized; no import written');
    }
    // Do not archive a corrupt snapshot or silently replace invalid state.
    final previous = TxSession.importJson(previousJson);
    previous.engine.checkInvariants();

    // One-way safety latch. No silent overwriting on a second import attempt;
    // even if a previous import stopped halfway, the archive is retained.
    if (prefs.containsKey(preImportSaveKey)) {
      throw StateError('Import already started; existing archive preserved');
    }
    final archived = await prefs.setString(preImportSaveKey, previousJson);
    if (!archived || prefs.getString(preImportSaveKey) != previousJson) {
      throw StateError('Failed to verify pre-import recovery snapshot');
    }

    // AFTER SharedPreferences reports completion of the pre-import copy,
    // replace the V0.1c snapshot. SharedPreferences is not transactional;
    // keep the archive and refuse trading if any write/read-back fails.
    final written = await prefs.setString(TxSession.saveKey, replacementJson);
    if (!written || prefs.getString(TxSession.saveKey) != replacementJson) {
      throw StateError('Failed to verify imported V0.1c snapshot');
    }
    final confirmed = TxSession.importJson(prefs.getString(TxSession.saveKey)!);
    confirmed.engine.checkInvariants();
    return confirmed;
  }
}
