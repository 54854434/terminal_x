import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/market/tx_market_profiles.dart';
import '../lib/market/tx_market_risk_core.dart';
import '../lib/market/tx_market_runtime.dart';
import '../lib/market/tx_market_venue.dart';
import '../lib/storage/tx_sqlite_store.dart';

TxMarketRuntime cryptoRuntime() => TxMarketRuntime(
      venue: TxMarketVenue(
        profile: TxMarketProfile.crypto,
        accounts: {
          'MAKER': TxMarketCore(
            profile: TxMarketProfile.crypto,
            openingCashCents: 1000000,
            initialMarks: {'SIM-BTCUSDT': 100000, 'SIM-ETHUSDT': 30000},
          ),
          'TAKER': TxMarketCore(
            profile: TxMarketProfile.crypto,
            openingCashCents: 1000000,
            initialMarks: {'SIM-BTCUSDT': 100000, 'SIM-ETHUSDT': 30000},
          ),
        },
      ),
      gameDay: 1,
      minuteOfDay: 10,
    );

void main() {
  test('independent market runtime uses a checksummed SQLite CAS envelope',
      () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      final runtime = cryptoRuntime();
      expect(await db.readMarketRuntime(TxMarketMode.crypto), isNull);

      final first = await db.saveMarketRuntime(runtime, expectedSequence: 0);
      expect(first.sequence, 1);
      final restored = await db.readMarketRuntime(TxMarketMode.crypto);
      expect(restored, isNotNull);
      expect(restored!.sequence, 1);
      expect(restored.runtime.exportJson(), runtime.exportJson());

      runtime.advanceClock(nextGameDay: 1, nextMinuteOfDay: 11);
      final second = await db.saveMarketRuntime(
          runtime, expectedSequence: restored.sequence);
      expect(second.sequence, 2);
      expect((await db.readMarketRuntime(TxMarketMode.crypto))!.runtime.minuteOfDay,
          11);

      await expectLater(
          db.saveMarketRuntime(runtime, expectedSequence: 1), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('corrupt independent runtime is rejected instead of replaced', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      await db.saveMarketRuntime(cryptoRuntime(), expectedSequence: 0);
      await db.customStatement(
          "UPDATE storage_metadata SET value='corrupt' "
          "WHERE key='market_runtime_v1_crypto'");
      await expectLater(
          db.readMarketRuntime(TxMarketMode.crypto), throwsStateError);
      await expectLater(
          db.saveMarketRuntime(cryptoRuntime(), expectedSequence: 1),
          throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('A-share remains outside the independent venue boundary', () async {
    final db = TxSqliteStore(NativeDatabase.memory());
    try {
      expect(() => TxMarketVenue(
            profile: TxMarketProfile.aShare,
            accounts: {'A': TxMarketCore.seeded(profile: TxMarketProfile.aShare)},
          ), throwsArgumentError);
      expect(await db.readMarketRuntime(TxMarketMode.aShare), isNull);
    } finally {
      await db.close();
    }
  });
}
