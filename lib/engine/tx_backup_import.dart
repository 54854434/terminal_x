/// Read-only validation of a V0.1b Android SharedPreferences XML backup.
///
/// This intentionally does NOT open local app storage, install an APK, or write
/// migrated data.  Callers must preview the returned TxSession and obtain
/// explicit user confirmation before implementing a future import commit.
import 'package:xml/xml.dart';

import 'tx_session.dart';

class TxBackupImport {
  static const int maxXmlCharacters = 8 * 1024 * 1024;

  /// Extract and validate the *exact* V0.1b session key from Android's
  /// FlutterSharedPreferences.xml. Returns a live, validated in-memory session.
  ///
  /// The "flutter." prefix is the on-disk convention of older
  /// shared_preferences Android implementations. Neither form is guessed
  /// from unrelated keys. A missing or duplicate key fails closed.
  static TxSession previewXml(String rawXml) {
    if (rawXml.isEmpty || rawXml.length > maxXmlCharacters) {
      throw const FormatException('Backup XML is empty or exceeds size limit');
    }
    // Do not permit any DTD/entity declarations from untrusted imports.
    if (RegExp(r'<!\s*(DOCTYPE|ENTITY)\b', caseSensitive: false)
        .hasMatch(rawXml)) {
      throw const FormatException('Backup XML must not contain a DTD');
    }

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(rawXml);
    } catch (_) {
      throw const FormatException('Backup XML could not be parsed');
    }

    final root = document.rootElement;
    if (root.name.local != 'map') {
      throw const FormatException('Not an Android preferences XML map');
    }

    final acceptedKeys = <String>{
      TxSession.saveKey,
      'flutter.${TxSession.saveKey}',
    };
    final matches = <XmlElement>[];
    for (final child in root.children) {
      if (child is XmlElement &&
          child.name.local == 'string' &&
          acceptedKeys.contains(child.getAttribute('name'))) {
        matches.add(child);
      }
    }
    if (matches.length != 1) {
      throw const FormatException(
          'Expected exactly one V0.1b session in XML backup');
    }
    // XML parser decodes &amp;, &lt; and other escaped text correctly.
    final snapshot = matches.single.innerText;
    if (snapshot.isEmpty || snapshot.length > maxXmlCharacters) {
      throw const FormatException('Session snapshot is empty or oversized');
    }

    try {
      // TxSession/TxEngine perform the authoritative schema, ledger,
      // cash/position reservation and order invariant checks.
      final session = TxSession.importJson(snapshot);
      session.engine.checkInvariants();
      return session;
    } catch (_) {
      // Avoid echoing raw private session data to logs or the user.
      throw const FormatException(
          'V0.1b snapshot failed session or accounting validation');
    }
  }
}
