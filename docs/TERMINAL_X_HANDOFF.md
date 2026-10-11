# Terminal X｜唯一持续交接文档

> **交接版本：v3.4｜更新日期：2026-10-12**  
> **GitHub 仓库：** https://github.com/54854434/terminal_x （Public，`main`）  
> **仓库内唯一规范路径：** `docs/TERMINAL_X_HANDOFF.md`  
> **本次核实的 `main` HEAD：** `2b17584ee97ee2c04eb9a07fd07ce1a72c8f9586`  
> **交接文件同步情况：** 远端 `docs/TERMINAL_X_HANDOFF.md` 已是 **v3.3**（blob `8b146661229d52bec4b447daca75ba1c92d579ca`）。本 **v3.4 已放入待上传的单 ZIP 补丁，尚未提交 GitHub**。不得声称已自动入库。  
> **当前最重要进度：2026-10-11 18:06 UTC 的 V0.2 Actions 第 8 次运行（ID `38162429194`，对应 `1ab38ab4`）已确认失败：61 项测试通过，1 项图表测试因 `WidgetTester.dragAt` 不存在而编译失败，APK 未开始构建。修复已封装在 `terminal_x_batch.zip`；另提供需一次性安装的 `tx-batch-import.yml` 自动批量整合工作流。两者尚未部署，切勿声称 V0.2 已通过或用户已验收。**

## 0. 用户环境、合作方式与不可违反的要求

1. 用户**只有 Android 手机，没有电脑**；通过手机 GitHub 网页上传文件，以 GitHub Actions 运行 Flutter/Dart 测试、构建 Android APK。**用中文简洁沟通**。从本版起采用“一次安装批量导入工作流，后续每批只上传一个 ZIP”，不要求解压并逐个上传源码。
2. **开发节奏已明确改为“批量开发 → 一次提交 → CI 全量回归 → 重要里程碑集中手机验收”**。不再为了每个小功能频繁要求下载 APK、截图和逐项反馈。安全底线及必要自动化测试不降低。
3. 用户明确决定：**正式版之前的模拟存档可以从新账户开始，不需要从 V0.1c 迁移任何资金/持仓/委托历史**。因此不再将旧存档迁移桥接作为 V0.2 的前置任务；但这不等于允许删除旧应用或备份。
4. **绝不要求卸载旧 V0.1b/V0.1c、清除应用数据或删除 Termux/Download 双份备份；不要将私人 XML 存档、密钥、令牌上传到公开 GitHub 或聊天。**不同预览 APK 使用独立包名。对未来同包名升级先核对签名及 versionCode；Actions debug 签名并不自动稳定。
5. 本次 GitHub 连接核实 `pull=true`、`push=false`：可以读取仓库，**不可声称已代用户提交代码/文档**。不要承诺后台自行完成工作。
6. 仓库只维护**一个规范交接 MD**：`docs/TERMINAL_X_HANDOFF.md`；重大里程碑覆盖更新旧内容，不建立多个日期或 `LATEST` 副本。MD 与源码一起封装进批量 ZIP，由工作流统一提交，不再单独要求用户上传交接文档。

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
| **V0.2 批量交易终端** | **9 个文件已上传**；已取得 V0.2 Actions #8 精确日志：**61 项通过，1 项图表测试编译失败**，已定位待修复。 | **V0.2 CI 未通过；APK 构建被跳过；手机实机仍未验收。** |

## 3. 当前 V0.2 源码、构建与架构

**最新已核实 `main` 提交：** [`2b17584ee97ee2c04eb9a07fd07ce1a72c8f9586`](https://github.com/54854434/terminal_x/commit/2b17584ee97ee2c04eb9a07fd07ce1a72c8f9586)（更新了 v3.3 交接 MD；V0.2 源码仍来自 `1ab38ab4`）。

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

**V0.2 新增 23 项测试用例已编写/上传。** 2026-10-11 Actions #8 运行时，整个回归批次报告 61 项通过、1 个测试文件编译失败；不可将通过数误述为全部测试通过。旧测试是 Actions 中的自动回归，不需要用户重复实机测试。

**重要运行参数（按现有代码）**：
- **构建工作流名**：`Build Terminal X V0.2 Batch Terminal (isolated)`；[工作流文件](https://github.com/54854434/terminal_x/blob/main/.github/workflows/build-v02-terminal.yml)。
- Flutter APK 入口：`lib/main_terminal_v02.dart`；`flutter build apk --debug --target lib/main_terminal_v02.dart`。
- 独立包名：`com.terminalx.v02.terminal_x`；APK Artifact：`terminal-x-v02-batch-terminal-apk`。
- Flutter 依赖配置仍位于 `pubspec.yaml`，包含 `drift: 2.32.1`、`crypto: 3.0.6`、`path_provider: ^2.1.5` 及既有依赖。
- 行情自动推进：默认暂停，仅 App 前台运行；1×/5×/10× 速度，单次最多推进 **60 步**。图表当前读取最近 **160 个**提交的快照。当前采用**完整快照历史表**，数据量、性能及长期归档仍待后续优化。
- `lib/main.dart` 仍是旧 V0.1c 入口；V0.2 独立入口和包名由新的工作流显式指定，不能混淆。
- 原生 Drift SQLite Android 运行已通过**独立探针**测试，不可直接宣称 V0.2 实机验证通过。

## 4. 本轮待办（已查明 CI 失败，不重跑旧实机验收）

1. **一次性建立自动整合机制**：先将 `tx-batch-import.yml` 放入仓库 `.github/workflows/tx-batch-import.yml`（只需安装一次），再将**原样、不要解压的** `terminal_x_batch.zip` 作为单文件上传至仓库根目录。工作流自动核验 ZIP 清单与前版本文件 SHA-256，合并、运行回归并编译独立 APK；仅在全部成功后提交源码、更新唯一交接 MD，并删除根目录 ZIP。
2. **本次确定性修复**：`test/tx_candle_chart_test.dart:23` 错误 `tester.dragAt(...)`，替换为 Flutter `WidgetTester.dragFrom(...)`；源码、交接 MD 已打包。原工作流第 8 次运行：https://github.com/54854434/terminal_x/actions/runs/38162429194。
3. **上传完成后复核新 Actions**：查看 `Terminal X - One ZIP Batch Import and APK` 的验证、测试、APK 构建、单次提交结果。**当前未运行这份新流程，不得预先宣称成功**。原 V0.2 流程失败时 APK 还未编译，后续可能存在新的构建错误，应依据实际日志再集中修复。
4. **全部 CI 通过后仅做一次集中手机里程碑验收**：四页、K 线触摸与缩放、两只 SIM 资产五档盘口、限价/市价买卖、冻结撤单、订单成交与资产联动、步进暂停/倍速、彻底关闭后 SQLite 数据恢复。保留所有旧 App 和备份。
5. **V0.2 实机验收通过才进入 V0.3 大批量功能迭代**，优先专业交易体验、委托管理/风控、数据量与性能。不要恢复 V0.1b XML 迁移前置任务，也不要让用户逐项重复原有测试。

## 5. 风险与严格安全底线

- V0.2 是**开发预览版**；正式版前数据可从新账户开始，但**仍不允许擅自删除、清空或覆盖旧 V0.1b/V0.1c 数据及私人备份**。私人 XML 只能存手机本地，不要上传 Public 仓库。
- 调试 APK 的签名可能随 GitHub Actions 运行环境变动；将来同包名升级须先验证签名一致及 versionCode 单调递增。稳定发布签名、可控升级/备份策略尚未完成。
- 交易写入应继续保持事务与账务不变量；数据库损坏、校验不通过、写入不确定时**停止交易并保留现场**，不得静默初始化新账户。
- 当前 SQLite 为每次操作保留**完整快照**，长期历史会增长；K 线由已记录快照生成，有限历史截断后的首根 K 线不能代表未记录时段真实 OHLC。后续应制定合理归档、结构化行情记录和性能测试。
- 严格区分：“用户手机实测”“Actions 日志确认”“用户报告 CI 绿色”“只完成代码/计划”，避免把它们混用。

## 6. 单 ZIP 批量上传与工作流固定协议（自 v3.4 起）

- **只安装一次**：将交付的 `tx-batch-import.yml` 上传到仓库的 `.github/workflows/`，形成 `.github/workflows/tx-batch-import.yml`；其后不要为每批功能再传一堆源码或多个脚本。此工作流独立于旧 V0.1c/V0.2 工作流。
- **每批只上传一个文件**：`terminal_x_batch.zip` 上传至仓库 `main` **根目录**，无需解压。内部必须有 `manifest.json` 与按真实仓库路径排列的源码/测试/`docs/TERMINAL_X_HANDOFF.md`；清单包含每个文件的 SHA-256 和旧文件 SHA-256，用于防误覆盖。
- **自动动作**：当该 ZIP 被推送到 `main`，工作流验证压缩包路径、大小、清单、逐文件摘要及旧版本前置条件，批量暂存文件，然后创建独立 Android 项目、安装 Flutter 依赖、运行清单指定的自动化回归、构建 debug APK、上传 Artifact。**全部成功后**，以一次 Git 提交写入源码与唯一交接文档，并从仓库根目录删除 ZIP；任何步骤失败则不提交源文件，查看该次 Actions 日志并在下一批替换 ZIP。
- **持续自动化**：固定工作流从每批清单读取 Android 组织 ID、应用 ID、入口、测试列表、显示名称及 APK Artifact 名；新功能/新测试/新入口都可在后续 ZIP 内更新，无需修改工作流。工作流的单次构建已经执行 CI；由 `GITHUB_TOKEN` 创建的提交**不会自动再触发其他 push 工作流**，不能等待旧 V0.2 Actions 出现新的运行来判断成功。
- **安全边界**：包中不允许 `.github/workflows/`、`.git/`、私人存档 XML、令牌和密钥。GitHub `GITHUB_TOKEN` 通常不能自动修改工作流 YAML；今后若确需改动工作流本身，再单独审核更新这一个引导文件，**不要求上传 PAT**。只在可信的 `main` 直推上运行，默认 `contents: write`；仓库分支保护或 Actions 权限若拒绝机器人推送，应查看日志并处理权限，而非绕过保护。
- **本次发布状态**：交付 `tx-batch-import.yml`（引导工作流）和 `terminal_x_batch.zip`（V0.2 测试修复 + v3.4 交接）。两者尚未由助手提交 GitHub；当前 GitHub 连接依然是 `pull=true` / `push=false`。

---

**新对话可直接发送**：  
“按 Terminal X v3.4 交接继续：已查实 V0.2 Actions #8 为 61 项通过、1 个 K 线测试 API 编译错误、APK 未编译；修复包使用根目录 `terminal_x_batch.zip` + 一次性导入工作流。先确认批量整合 Actions 和 APK 构建，绿色后再集中手机验收；只有 Android 手机，不重复旧存档、迁移或小测试。”
