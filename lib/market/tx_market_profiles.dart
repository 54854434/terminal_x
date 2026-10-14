import 'tx_market_instruments.dart';
import 'tx_market_session_schedule.dart';

/// Market-mode definitions shared by the terminal UI and independent
/// instrument/risk/venue cores. The connected A-share ledger remains a
/// separate runtime path and is never relabeled as another market.
enum TxMarketMode { aShare, usEquity, futures, crypto, forex }

class TxMarketProfile {
  const TxMarketProfile({
    required this.mode,
    required this.label,
    required this.category,
    required this.quoteCurrency,
    required this.session,
    required this.settlement,
    required this.orderUnit,
    required this.tickSize,
    required this.maxLeverage,
    required this.supportsShort,
    required this.coreStatus,
    required this.independentCoreProgress,
    required this.instruments,
    required this.schedule,
  });

  final TxMarketMode mode;
  final String label;
  final String category;
  final String quoteCurrency;
  final String session;
  final String settlement;
  final String orderUnit;
  final String tickSize;
  final String maxLeverage;
  final bool supportsShort;
  final String coreStatus;
  /// Progress of the independent account/risk boundary, not runtime
  /// connectivity. A mode is not tradeable merely because this is non-zero.
  final double independentCoreProgress;
  final List<TxMarketInstrument> instruments;
  final TxMarketSessionSchedule schedule;

  bool get isCoreConnected => mode == TxMarketMode.aShare;

  static const aShare = TxMarketProfile(
    mode: TxMarketMode.aShare,
    label: 'A股',
    category: '股票现货',
    quoteCurrency: 'CNY',
    session: '交易时段 09:30–15:00',
    settlement: 'T+1 规则预览',
    orderUnit: '股',
    tickSize: '¥0.01',
    maxLeverage: '1×',
    supportsShort: false,
    coreStatus: '当前现货撮合核心已连接 · 交易时段门禁已接入 · 尚未接入卖空',
    independentCoreProgress: 1.0,
    schedule: TxMarketSessionSchedules.aShare,
    instruments: [
      TxMarketInstrument(
        symbol: 'SIM-A01', name: '模拟 A 股 01', kind: '股票现货',
        quoteCurrency: 'CNY', orderUnit: '股', lotSize: 1,
        tickSize: '¥0.01', contractMultiplier: '1 股',
        contractMultiplierUnits: 1, usesMargin: false, tPlusOne: true,
        supportsShort: false, coreConnected: true,
      ),
      TxMarketInstrument(
        symbol: 'SIM-A02', name: '模拟 A 股 02', kind: '股票现货',
        quoteCurrency: 'CNY', orderUnit: '股', lotSize: 1,
        tickSize: '¥0.01', contractMultiplier: '1 股',
        contractMultiplierUnits: 1, usesMargin: false, tPlusOne: true,
        supportsShort: false, coreConnected: true,
      ),
    ],
  );

  static const usEquity = TxMarketProfile(
    mode: TxMarketMode.usEquity,
    label: '美股',
    category: '股票现货',
    quoteCurrency: 'USD',
    session: '交易时段 21:30–04:00（模拟）',
    settlement: 'T+1 规则预览',
    orderUnit: '股',
    tickSize: '\$0.01',
    maxLeverage: '2× 预览',
    supportsShort: true,
    coreStatus: '规则层、风控、撮合、快照、费率、行情标记、原子日结与运行时协议已接入 · SQLite 独立快照边界已完成 · Flutter/Rust 接线开发中',
    independentCoreProgress: 0.92,
    schedule: TxMarketSessionSchedules.usEquity,
    instruments: [
      TxMarketInstrument(
        symbol: 'SIM-US01', name: '模拟美股科技', kind: '股票现货',
        quoteCurrency: 'USD', orderUnit: '股', lotSize: 1,
        tickSize: '\$0.01', contractMultiplier: '1 股',
        contractMultiplierUnits: 1, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
      TxMarketInstrument(
        symbol: 'SIM-US02', name: '模拟美股价值', kind: '股票现货',
        quoteCurrency: 'USD', orderUnit: '股', lotSize: 1,
        tickSize: '\$0.01', contractMultiplier: '1 股',
        contractMultiplierUnits: 1, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
    ],
  );

  static const futures = TxMarketProfile(
    mode: TxMarketMode.futures,
    label: '期货',
    category: '保证金合约',
    quoteCurrency: 'CNY',
    session: '日盘/夜盘由合约配置',
    settlement: '每日盯市',
    orderUnit: '手',
    tickSize: '合约最小变动',
    maxLeverage: '10× 预览',
    supportsShort: true,
    coreStatus: '规则层、风控、撮合、快照、费率、行情标记、原子日结与运行时协议已接入 · SQLite 独立快照边界已完成 · Flutter/Rust 接线开发中',
    independentCoreProgress: 0.92,
    schedule: TxMarketSessionSchedules.futures,
    instruments: [
      TxMarketInstrument(
        symbol: 'SIM-FUT01', name: '模拟股指合约', kind: '期货合约',
        quoteCurrency: 'CNY', orderUnit: '手', lotSize: 1,
        tickSize: '0.2 点', contractMultiplier: '300 CNY/点',
        contractMultiplierUnits: 300, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
      TxMarketInstrument(
        symbol: 'SIM-FUT02', name: '模拟商品合约', kind: '期货合约',
        quoteCurrency: 'CNY', orderUnit: '手', lotSize: 1,
        tickSize: '1 点', contractMultiplier: '10 CNY/点',
        contractMultiplierUnits: 10, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
    ],
  );

  static const crypto = TxMarketProfile(
    mode: TxMarketMode.crypto,
    label: '虚拟货币',
    category: '现货/永续',
    quoteCurrency: 'USDT',
    session: '7×24 小时',
    settlement: '实时结算/资金费率',
    orderUnit: '币',
    tickSize: '按交易对配置',
    maxLeverage: '20× 预览',
    supportsShort: true,
    coreStatus: '规则层、风控、撮合、快照、费率、行情标记、原子日结与运行时协议已接入 · SQLite 独立快照边界已完成 · Flutter/Rust 接线开发中',
    independentCoreProgress: 0.92,
    schedule: TxMarketSessionSchedules.crypto,
    instruments: [
      TxMarketInstrument(
        symbol: 'SIM-BTCUSDT', name: '模拟 BTC 永续', kind: '虚拟货币永续',
        quoteCurrency: 'USDT', orderUnit: '币', lotSize: 1,
        tickSize: '0.1 USDT', contractMultiplier: '1 币',
        contractMultiplierUnits: 1, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
      TxMarketInstrument(
        symbol: 'SIM-ETHUSDT', name: '模拟 ETH 现货', kind: '虚拟货币现货',
        quoteCurrency: 'USDT', orderUnit: '币', lotSize: 1,
        tickSize: '0.01 USDT', contractMultiplier: '1 币',
        contractMultiplierUnits: 1, usesMargin: false, tPlusOne: false,
        supportsShort: false, coreConnected: false,
      ),
    ],
  );

  static const forex = TxMarketProfile(
    mode: TxMarketMode.forex,
    label: '外汇',
    category: '货币对保证金',
    quoteCurrency: 'USD',
    session: '5×24 小时（模拟）',
    settlement: '保证金滚动',
    orderUnit: '标准手',
    tickSize: '点/小数位配置',
    maxLeverage: '30× 预览',
    supportsShort: true,
    coreStatus: '规则层、风控、撮合、快照、费率、行情标记、原子日结与运行时协议已接入 · SQLite 独立快照边界已完成 · Flutter/Rust 接线开发中',
    independentCoreProgress: 0.92,
    schedule: TxMarketSessionSchedules.forex,
    instruments: [
      TxMarketInstrument(
        symbol: 'SIM-EURUSD', name: '模拟欧元/美元', kind: '外汇货币对',
        quoteCurrency: 'USD', orderUnit: '标准手', lotSize: 1,
        tickSize: '0.0001', contractMultiplier: '100,000 EUR',
        contractMultiplierUnits: 100000, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
      TxMarketInstrument(
        symbol: 'SIM-USDJPY', name: '模拟美元/日元', kind: '外汇货币对',
        quoteCurrency: 'USD', orderUnit: '标准手', lotSize: 1,
        tickSize: '0.01', contractMultiplier: '100,000 USD',
        contractMultiplierUnits: 100000, usesMargin: true, tPlusOne: false,
        supportsShort: true, coreConnected: false,
      ),
    ],
  );

  static const values = <TxMarketProfile>[
    aShare,
    usEquity,
    futures,
    crypto,
    forex,
  ];

  static TxMarketProfile of(TxMarketMode mode) => values.firstWhere(
      (profile) => profile.mode == mode);
}
