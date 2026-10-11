# Terminal X｜唯一持续交接文档

> **交接版本：v3.3｜更新日期：2026-10-12**  
> **GitHub 仓库：** https://github.com/54854434/terminal_x （Public，`main`）  
> **仓库内唯一规范路径：** `docs/TERMINAL_X_HANDOFF.md`  
> **本次核实的 `main` HEAD：** `1ab38ab4c9a2f26cc5a04a7cbbf0be77f4c90e4f`  
> **交接文件同步情况：** 当前远端 `docs/TERMINAL_X_HANDOFF.md` 仍是 **v3.2**（blob `925ec533cb7a456ca87792a9c8bbf862269def1e`），其“V0.1c 交易回归尚未完成”等内容已过时。本 **v3.3 在本次对话中生成，尚未提交到 GitHub**。新对话请优先采用本文，并重新核对最新提交。  
> **当前最重要进度：V0.2 专业交易终端 9 个源码/测试/工作流文件已上传到 GitHub，且逐一核对与交付 ZIP 一致；尚未取得 V0.2 Actions 成功日志或手机实机验收记录。下一步先核对 V0.2 Actions，失败则集中修复；成功则做一次集中手机验收。**

## 0. 用户环境、合作方式与不可违反的要求

1. 用户**只有 Android 手机，没有电脑**；通过手机 GitHub 网页批量上传文件，以 GitHub Actions 运行 Flutter/Dart 测试、构建 Android APK。**用中文简洁沟通**，不要求反复讲解背景、上传交接 MD，也无需逐个文件教学。用户会解压 ZIP 并按目录上传。
2. **开发节奏已明确改为“批量开发 → 一次提交 → CI 全量回归 → 重要里程碑集中手机验收”**。不再为了每个小功能频繁要求下载 APK、截图和逐项反馈。安全底线及必要自动化测试不降低。
3. 用户明确决定：**正式版之前的模拟存档可以从新账户开始，不需要从 V0.1c 迁移任何资金/持仓/委托历史**。因此不再将旧存档迁移桥接作为 V0.2 的前置任务；但这不等于允许删除旧应用或备份。
4. **绝不要求卸载旧 V0.1b/V0.1c、清除应用数据或删除 Termux/Download 双份备份；不要将私人 XML 存档、密钥、令牌上传到公开 GitHub 或聊天。**不同预览 APK 使用独立包名。对未来同包名升级先核对签名及 versionCode；Actions debug 签名并不自动稳定。
5. 本次 GitHub 连接核实 `pull=true`、`push=false`：可以读取仓库，**不可声称已代用户提交代码/文档**。不要承诺后台自行完成工作。
6. 仓库只维护**一个规范交接 MD**：`docs/TERMINAL_X_HANDOFF.md`；重大里程碑再覆盖更新旧内容，不建立多个日期或 `LATEST` 副本。每轮不必强迫用户同步文档。

## 1. 产品与引擎边界

- **产品**：Android 离线、单人、专业深色金融交易与大资金操盘模拟器；不是实盘交易，也不是社交/剧情游戏。Flutter/Dart 开发，当前资产为两只合成股票：`SIM-A01`（较高流动性）及 `SIM-A02`（较低流动性）。
- **已实现的交易基础**：有限库存/现金的做市商、真实五档盘口、价格优先及同价 FIFO、限价/市价委托、部分成交、资金/持仓冻结、撤单、行情步进、整数分资金账、订单/成交/账本守恒检查；跨档成交才会产生滑点，不允许凭空拉价。
- **长期规划，不得误认为已完成**：不同市场的交易时段和 T+0/T+1、费用/结算、保证金和杠杆、期货/外汇/加密资产、订单风控、TWAP/VWAP、分支存档、策略等。
- **数据原则**：所有账务变动须可解释、校验并完整持久化；读取损坏存档时停止操作，不可静默重置成新账户。

## 2. 已确认里程碑（事实与验证边界）

| 阶段 | 已证实内容 | 不能据此推断 |
|---|---|---|
| V0.1b | Actions 17/17 测试及 APK 构建通过；用户 Android 真机完成 10/10 交易和恢复验收。 | 不代表长时间压力测试。 |
| V0.1b 备份 | 用户以 Termux + ADB `run-as` 只读备份 `FlutterSharedPreferences.xml`，原始大小 **432,850 字节**，源文件与备份 SHA-256 相同；Termux 私有目录及 Download 各一份。 | 助手未接触私人 XML；勿公开上传。 |
| V0.1c | 独立包名 `com.terminalx.v01c.terminal_x`，旧 V0.1b 为 `com.terminalx.preview.terminal_x`。旧版 XML 预览、账务验证、确认导入及完全关闭后重开数据一致，**用户手机已验收通过**。 | 不是 SQLite 存储。 |
| V0.1c 交易回归 | 用户反馈 **5/5 项实机通过**：初始数据确认、市价买卖、限价买单冻结撤单、卖单冻结及拒单、行情步进及彻底关闭后恢复。 | SIM-A02 跨档滑点专项未单独报手机结果，已有引擎自动测试。 |
| V0.1d SQLite 模块 | 增加 `lib/storage/tx_sqlite_store.dart`（Drift + SQLite、完整 JSON 快照、事务、SHA-256 校验、修订号、拒绝错误状态）；首批 11 项安全测试加入 Actions。用户报告 Actions 绿色。 | 这不是正式版数据迁移完成。 |
| V0.1d 独立 SQLite 探针 | 独立包名 `com.terminalx.storageprobe.terminal_x`，使用合成数据。用户两次手机截图：第一次修订 **2**、步数 **1**、初始创建“是”；彻底关闭重开后再次运行修订 **3**、步数 **2**、初始创建“否”、冻结资金 **4000 分**，订单/成交与摘要校验通过。**Android SQLite 跨 App 重启持久化验收通过。** | 仅探针通过，不代表 V0.2 交易 APK 已验收。 |
| V0.1d 迁移桥接 | 曾生成并上传只读预览/确认桥接和测试，但用户随后明确放弃继承 V0.1c 数据。 | 不再作为当前开发前置条件。 |
| **V0.2 批量交易终端** | **9 个文件已上传到 GitHub，逐个 Git blob 与原交付 ZIP 一致**；代码包含专业页面、图表、订单及 SQLite 服务。 | **本次尚未核实 V0.2 CI 绿色及手机运行成功。** |

## 3. 当前 V0.2 源码、构建与架构

**最新已核实提交：** [`1ab38ab4c9a2f26cc5a04a7cbbf0be77f4c90e4f`](https://github.com/54854434/terminal_x/commit/1ab38ab4c9a2f26cc5a04a7cbbf0be77f4c90e4f)。

**V0.2 上传包：** `terminal_x_v02_batch_upload.zip`，共 **9 个文件**，现已存在于远端 `main`；不要在新对话重复让用户上传同一包，除非发现更新或修复需要。组成如下：

| 路径 | 功能 |
|---|---|
| `lib/main_terminal_v02.dart` | V0.2 独立入口、专业深色界面、行情/交易/资产/记录四页、盘口及行情暂停/倍速控制。 |
| `lib/market/tx_candle_history.dart` | 从**已提交且验证的 SQLite 历史会话快照**计算逐模拟步 K 线和成交量；不是外部市场数据，不凭空补全缺失历史。 |
| `lib/widgets/tx_candle_chart.dart` | K 线绘制、触摸滚动及缩放。 |
| `lib/storage/tx_trading_service.dart` | 复制会话、撮合、校验、SQLite 成功提交后才更新内存展示；失败锁定后续操作。 |
| `lib/storage/tx_sqlite_store.dart` | 在旧实验模块上增加全新数据库初始化和校验后的历史快照读取。 |
| `test/tx_trading_service_test.dart` | 10 项交易服务与持久化测试。 |
| `test/tx_candle_history_test.dart` | 11 项 K 线历史/数据正确性测试。 |
| `test/tx_candle_chart_test.dart` | 2 项图表组件测试。 |
| `.github/workflows/build-v02-terminal.yml` | 一次运行旧引擎、SQLite、新交易服务与图表回归，并构建独立 APK。 |

**合计 V0.2 新增 23 项测试用例已编写/上传，是否通过待查 Actions 日志**。旧测试亦在同一工作流内执行。

**重要运行参数（按现有代码）**：
- **构建工作流名**：`Build Terminal X V0.2 Batch Terminal (isolated)`；[工作流文件](https://github.com/54854434/terminal_x/blob/main/.github/workflows/build-v02-terminal.yml)。
- Flutter APK 入口：`lib/main_terminal_v02.dart`；`flutter build apk --debug --target lib/main_terminal_v02.dart`。
- 独立包名：`com.terminalx.v02.terminal_x`；APK Artifact：`terminal-x-v02-batch-terminal-apk`。
- Flutter 依赖配置仍位于 `pubspec.yaml`，包含 `drift: 2.32.1`、`crypto: 3.0.6`、`path_provider: ^2.1.5` 及既有依赖。
- 行情自动推进：默认暂停，仅 App 前台运行；1×/5×/10× 速度，单次最多推进 **60 步**。图表当前读取最近 **160 个**提交的快照。当前采用**完整快照历史表**，数据量、性能及长期归档仍待后续优化。
- `lib/main.dart` 仍是旧 V0.1c 入口；V0.2 独立入口和包名由新的工作流显式指定，不能混淆。
- 原生 Drift SQLite Android 运行已通过**独立探针**测试，不可直接宣称 V0.2 实机验证通过。

## 4. 新对话第一优先任务（不要重新做旧备份/迁移）

1. **先核查最新 `main` 与 [V0.2 Actions](https://github.com/54854434/terminal_x/actions/workflows/build-v02-terminal.yml)**。确认关联最新 V0.2 提交的测试步骤、APK 构建步骤、运行编号与日志。用户本轮尚未汇报 V0.2 的构建结果；**不能凭源码存在、工作流存在或以前的绿色测试声称 V0.2 已通过**。
2. **若 CI 失败**：依据准确日志定位，集中修复为一个 ZIP 批量交付；保留旧引擎约束，不要给用户多个零碎修补包。修复后再次校验 Actions。
3. **若 CI 全绿**：下载 V0.2 独立 APK 做**一次集中** Android 里程碑验收：四个页面、K 线滑动/缩放、SIM-A01/A02 五档盘口、限价/市价买卖、冻结与撤单、订单/成交/资产联动、步进和前台暂停/倍速、彻底关闭后 SQLite 数据恢复。缺陷集中反馈一次。旧应用和备份保留。
4. **通过 V0.2 验收后**：进入下一批 V0.3 开发，优先做交易终端专业化、操作体验、风控/委托管理、数据规模与性能优化；继续“单批多功能 + CI 自动测试 + 重要版本才实机验收”。不要倒回 V0.1b XML 导入流程。
5. 用户暂未要求将本 v3.3 MD 立即提交到 GitHub。需更新远端时，只覆盖 `docs/TERMINAL_X_HANDOFF.md` 同一路径，不新建交接副本；更新前重新核对 `HEAD`。

## 5. 风险与严格安全底线

- V0.2 是**开发预览版**；正式版前数据可从新账户开始，但**仍不允许擅自删除、清空或覆盖旧 V0.1b/V0.1c 数据及私人备份**。私人 XML 只能存手机本地，不要上传 Public 仓库。
- 调试 APK 的签名可能随 GitHub Actions 运行环境变动；将来同包名升级须先验证签名一致及 versionCode 单调递增。稳定发布签名、可控升级/备份策略尚未完成。
- 交易写入应继续保持事务与账务不变量；数据库损坏、校验不通过、写入不确定时**停止交易并保留现场**，不得静默初始化新账户。
- 当前 SQLite 为每次操作保留**完整快照**，长期历史会增长；K 线由已记录快照生成，有限历史截断后的首根 K 线不能代表未记录时段真实 OHLC。后续应制定合理归档、结构化行情记录和性能测试。
- 严格区分：“用户手机实测”“Actions 日志确认”“用户报告 CI 绿色”“只完成代码/计划”，避免把它们混用。

---

**新对话可直接发送**：  
“请按我上传的 Terminal X v3.3 交接文档继续。V0.1c 交易回归已实机通过、V0.1d SQLite 探针跨 App 重启已实机通过；我已决定正式版前不迁移旧模拟存档。V0.2 的 9 个文件已经上传 GitHub，先查 `main` 和 V0.2 Actions，确认构建结果后集中验收或批量修复。只有 Android 手机，请勿让我重复旧备份或逐项小测试。”
