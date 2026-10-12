# Terminal X｜唯一持续交接文档

**交接版本：v4.1（V0.2.4 开发候选／精确仓库清理）｜2026-10-12**

- **仓库**：`https://github.com/54854434/terminal_x`，主分支 `main`。
- **规范交接路径**：`docs/TERMINAL_X_HANDOFF.md`（仅此一份，下一批可全面修改产品设计、玩法及技术路线，不是永久不变的规范）。
- **最新已确认基线**：Terminal X `0.2.3+23`，GitHub Actions `38186437378` 全部成功，SHA `6c38e2ac6c7347ca9127ea94a300f40d628c1039`；ARM64 Release APK 约 20.3 MB，Artifact ZIP 9,907,009 字节，RSA 3072 签名已验证。GitHub 中正式源码合并且按明确清单删除 5 个废弃文件；5 个旧 CI 工作流已禁用而不是删除。
- **本批范围**：准备 `0.2.4+24`，单 ZIP 源码与图标，**截至交接文档制作时尚未提交 CI、没有真实 APK、没有通过实机验收**；不得将“已编写代码”误说成“已修复通过”。

## 1. 产品和用户要求

Android、离线、单机、专业深色的证券交易与大资金模拟；当前两只合成标的 `SIM-A01`、`SIM-A02`。用户只有 Android 手机，使用 GitHub 手机网页上传一次 ZIP，让工作流在服务器上验证、编译、提交。批量开发后重要里程碑集中验收，不重复此前通过的旧版手机测试。

**所有路线图、功能优先级、图标风格和玩法均可根据用户体验继续调整。** 不可改变的是账务真实性、安全边界和兼容性：有限资金/库存、真实撮合的成交量、不凭空增添玩家收益、不擦除私人备份或已安装旧应用、错误存档禁止静默清空。

## 2. 本轮用户实测反馈

V0.2.3 Android 手机用户已安装并反馈：
1. 需要有辨识度的 Terminal X 应用图标；用户指定一幅深蓝背景、青绿渐变大 X、金融蜡烛图元素的图片，原图为聊天中生成并确认的图标。
2. 持仓页无法查看成本价、持仓成本、浮盈/浮亏、收益率和已实现收益。
3. K 线不像实时行情那样分钟内来回变化，缺少移动均线。
4. 历史 K 线越来越多和高倍速时缩放、滑动卡顿；保存全量会话快照也造成长期性能风险。
5. 下单操作繁琐，需要常用数量快捷填充、价格档位和持仓快捷交易。

此轮优先解决显示和交互性能层，不擅自声称已经实现真实的秒级交易撮合或消除了数据库无限增长风险。

## 3. V0.2.4 候选包改动

- **图标**：在 `assets/launcher/icon_master.png` 保存高分辨率主图；Android 五种 DPI 对应 `assets/launcher/android/{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`。新版 `.github/workflows/tx-batch-import.yml` 在 `flutter create` 后、构建前将五个 PNG 覆盖到 `android/app/src/main/res/mipmap-*/ic_launcher.png`；缺文件则失败，**不使用默认 Flutter 图标**。工作流必须先手动更新一次，才上传单 ZIP；它不能通过受限 manifest 自己修改 `.github/`。
- **持仓分析**：新增 `lib/market/tx_position_analytics.dart`，仅从引擎真实成交明细、订单买卖方向计算移动加权平均持仓成本（整数分，卖出时合理分摊成本）、累计已实现收益、最新已提交市场标记价下的浮动收益、收益率；无法解释起始库存时明确标记“不可核算”，不编造成本。不改变引擎账务和存储 schema，旧 V0.2.3 SQLite 可原地读取。收益**不包括未来尚未实现的交易费用税费**，不代表真实投资回报。
- **均线**：`lib/market/tx_indicators.dart` 由已校验、已提交的 K 线收盘价计算 SMA5/10/20，历史不足时不补数。支持开关。
- **秒级指示报价**：`lib/market/tx_quote_preview.dart` 在每个游戏秒的前台 UI 展示确定性、有限幅度的模拟参考价格波动；空心预览 K 棒与虚线明确注明“指示价，不是已成交价”，绝不写入 SQLite、改变成交记录或造假成交量；真正的成交、真实一分钟 OHLC 仍以撮合引擎提交为准。实现真正的秒级订单簿/逐笔撮合是后续架构任务。
- **图表性能**：每秒仅通知时钟、报价及 K 线局部控件，不再因秒钟刷新触发整个 Scaffold、盘口和记录页构建；`TxLiveCandles` 缓存只读视图而不是每秒复制 K 线列表；图表仅绘制可见窗口（12–80 根）、用 `RepaintBoundary` 隔离绘制。历史全量快照成本仍有上限风险，**不能宣称所有卡顿已经解决**。
- **交易快捷方式**：增加快捷买入/卖出入口、1/10/100/500 股、可卖全部、按卖一估算的半仓买入、快速填买一/卖一限价；最终资金/库存校验仍由原引擎负责，估算不是成交保证。
- **版本与覆盖**：`pubspec.yaml` 升至 `0.2.4+24`，Android 包名固定 `com.terminalx.game.terminal_x`、桌面名称 `Terminal X`；必须继续使用此前保存的**相同 GitHub Actions 私密密钥**构建 ARM64 Release，不公开签名凭据。理论上可覆盖 V0.2.3 并保留相同包名下 SQLite 存档。只能在手机实际升级后将“覆盖升级成功”标为通过。
- **仓库**：新稳定入口 `lib/main_terminal.dart`，`lib/main.dart` 导向该入口。经 ZIP SHA-256 校验及 CI 编译通过后再删除已淘汰 `lib/main_terminal_v023.dart`，不清除账务/备份/SQLite 测试。

## 4.1 仓库文件清理（本次新增，安全优先）

用户要求整合 `lib/`、`test/`、`.github/workflows/` 的已废弃文件，而不只停用旧 CI。

- **主发布事务（6 文件）：** 在 V0.2.4 全量回归、签名 ARM64 Release APK、Artifact 上传都成功后，按 ZIP manifest 中精确 SHA-256 删除 `lib/main_terminal_v023.dart`、`lib/engine/tx_backup_commit.dart`、`lib/storage/tx_migration_bridge.dart`、`test/tx_backup_commit_test.dart`、`test/tx_migration_bridge_test.dart`、`test/tx_v021_market_test.dart`。这几个组件属于已放弃的 V0.1c XML 导入提交流程、旧 SQLite 迁移桥，以及不符合现今时钟模型的 V0.2.1 旧倍速测试。旧文件仍保留在 Git 历史，用户的手机私有备份/旧应用完全不受仓库删文件影响。
- **仍然保留**：`lib/engine/tx_engine.dart`、`lib/engine/tx_session.dart`、`lib/engine/tx_backup_import.dart`（仍由 `test/tx_session_test.dart` 引用以测试旧存档的只读安全解析）、`lib/market/tx_simulation_clock.dart`（当前新 UI 仍用于分钟/日期换算）、`lib/storage/tx_sqlite_store.dart` 及所有现行市场、持仓/盈亏、均线、实时钟、图表测试。仅凭文件名带旧版本号不构成删除依据。
- **旧工作流（5 文件）：** `build-apk.yml`、`build-storage-probe.yml`、`build-v02-terminal.yml`、`v01b-engine-validation.yml`、`v01c-signature-audit.yml` 已被上版 CI 禁用。新导入工作流在**主 APK 已构建、源码已提交成功之后**，另起独立 Job，用精确 SHA-256 尝试提交删除这些 YAML，只保留 `tx-batch-import.yml`。若 GitHub 的 `GITHUB_TOKEN` 因 workflow 编辑权限不足拒绝 push，只记录警告、不撤销 V0.2.4 APK 与已验证源码；届时用户需在 GitHub 网页一次性手动删除那五个已禁用 YAML。不可把“Job 运行成功”误报为“五个文件已删”，必须检查 GitHub 最新树。
- **CI 完整性**：测试列表必须覆盖全部未删除的 `test/tx_*_test.dart`；所有还在使用的 Dart 文件不允许 import 已标记删除的模块。仅对明确旧文件加白名单；每一条删除都必须按仓库当前 SHA-256 检查，禁止通配符或目录清空。旧历史版本可从 Git 查看，不删除手机存档或仓库 Git 历史。

## 4. CI 上传步骤与验证边界

1. 首先用该批次附带的 `tx-batch-import.yml` **覆盖 `.github/workflows/tx-batch-import.yml` 并提交**。仅改两处：在 Android 工程生成后从 ZIP 复制已验证 PNG 资源为桌面图标，以及允许 SHA-256 锁定删除上版 `lib/main_terminal_v023.dart`。原校验、测试、签名、发布机制必须保持。
2. 再将本批 `terminal_x_batch.zip` 原样上传至 GitHub **根目录**提交。ZIP 采用既有 manifest schema=1、文件 SHA-256 和 existing-file previous_sha256、严格的 `0.2.4+24`、固定包名和签名 ARM64 Release。
3. 等待 Actions 所有测试、签名 Release APK、Artifact 上传、主事务旧文件清理及提交全部通过；旧 workflow YAML 独立自动清理需额外核对 Git 树，核对新 Artifact 大小及 app 版本。Flutter SDK 不在本地文件制作环境中，因此这批**没有本地 Dart/Flutter 编译结果**。
4. 用户仅需定向真机验收：0.2.3 同包覆盖安装并保存旧账户；桌面新 X 图标；先买入，再核对成本/浮盈/卖出已实现损益；查看 MA5/10/20 和缩放；高倍速 60 分钟与暂停后检查交互是否改善。旧版已通过的账户冻结/撤单及旧包备份不重复手工测试。

## 5. 风险与后续技术方向（可更改）

- 当前 60× 最多每现实秒落一次完整游戏分钟，同时 SQLite 每次存**完整会话快照**，长期游戏时订单、成交和账本累积，序列化与快照数据仍逐渐增大。计划下一轮以事件表或分段快照、分页读取历史、完整性链表及归档策略重构，必须先测试恢复与账本守恒，不要简单删除订单/成交历史。
- 目前秒级指示价**不等于真实秒级撮合和分钟内真实价量波动**。若下一轮主要关注行情真实性，应提升 NPC 事件调度为秒级，真实限价簿随事件变化；K 线由真实逐笔聚合，可设计 1s/5s/1m/5m 周期而非随机造图。
- 成本核算采用移动加权平均，无佣金税费模块。若推出手续费、分红、股票拆分、融券或存量迁移，需要增加带版本号的成交成本账本，不可默认旧仓拥有零成本。
- 系统私钥仅存于用户私人备份与 GitHub Secrets，不在公共仓库/ZIP/文档；不可要求删除旧版或私人备份。旧版历史和 GitHub 里既往 workflow 文件可供审计，但已经禁用旧自动构建。
