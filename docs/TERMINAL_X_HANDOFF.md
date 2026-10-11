# Terminal X｜唯一持续交接文档

> **交接版本**：v3.2｜**更新日期**：2026-10-12  
> **仓库**：https://github.com/54854434/terminal_x（Public，`main`）  
> **唯一规范路径**：`docs/TERMINAL_X_HANDOFF.md`  
> **最近核实 main HEAD**：`21e68a5f8edcfc1653bd1da86ac9553ab09f0416`  
> **远端规范交接现状**：截至此次核对，GitHub 上 `docs/TERMINAL_X_HANDOFF.md` 仍是 **v2.6**（blob `ba6c8087a9f43b6a64c098b71f296e091b08d082`），内容已经过时。**本 v3.2 文件已在对话中生成，尚未上传或提交 GitHub**。新对话以本文记录的已验收事实为起点，同时重新核对仓库新提交。  
> **当前进度**：**V0.1c 独立 APK 已在用户安卓手机上完成旧 V0.1b 存档预览、确认导入、完全关闭后重新打开的数据恢复验收，用户反馈全部一致。**下一项是导入后的交易回归测试；其后规划 SQLite/Drift 持久化升级。

## 0. 新对话工作协议与用户环境

1. **用户只有一台 Android 手机，没有电脑**。Flutter/Dart 开发依赖 GitHub 手机网页上传及 GitHub Actions 云端测试、APK 构建；本次核对 GitHub 连接有读取权限，没有 `push` 权限，不能声称已代为提交。回复用中文，步骤明确但**不必机械地逐个文件教学**；用户已能够自行解压和批量上传 ZIP 中的文件。
2. 新会话先核对 GitHub `main`、规范交接、核心代码与相关 Actions。严格区分 **用户手机已实测 / Actions 测试日志已核实 / 用户报告绿色构建 / 尚未测试或仅计划**，不能用绿色 CI 代替真实手机验收。
3. **仅维护一个交接 MD**：`docs/TERMINAL_X_HANDOFF.md`。在重大里程碑或切换对话时集中生成/同步最新版；不要每轮要求用户手工上传、不要创建 `LATEST`、日期版本或重复交接文件到仓库。修改时更新既有状态章节，不累积长篇旧版本历史。用户此时只是索取下载文档，**不意味着要求立即上传 GitHub**。
4. 核心交易约束：价格优先、同价 FIFO；整数分资金账、库存/现金有限的做市商；资金与持仓冻结、订单、成交和账本一致；大单跨盘口导致真实滑点，不允许无成交直接拉价。持续测试、保护已验收功能。
5. **数据安全优先**：绝不卸载/覆盖已验收的 V0.1b，不清除其数据；不删除 V0.1c 或 Termux 备份；不在聊天或 Public GitHub 上传私人存档 XML、令牌、私钥。没有稳定签名/迁移路径前，不假定未来 debug APK 可以原地升级。删除/恢复操作须有清晰可验证的回退方案。不要承诺后台自行工作。

## 1. 产品和技术边界

- **产品**：Terminal X，安卓离线单人金融交易及大资金操盘模拟器，专业深色交易终端；不是实际证券交易，不是网络社交或剧情游戏。
- **已落地的 V0.1 范围**：两只合成股票 `SIM-A01`（流动性较高）、`SIM-A02`（较低）；本地撮合引擎、限价/市价委托、冻结/撤单、部分成交、有限做市商、行情步进、账务与快照恢复。
- **长期规划**：A 股、美股、期货、外汇、加密资产各自的交易时段、结算、T+1/T+0、费用、杠杆和保证金规则；交互 K 线、专业盘口、风控、TWAP/VWAP、暂停/倍速、无限模拟、分支存档及本地策略。**这些不是当前已完成功能**。
- **当前技术栈**：Flutter/Dart；GitHub Actions 编译 Android debug APK；`shared_preferences` 保存完整 JSON 会话；Android XML 备份解析使用 `xml`；系统文件选择使用 `file_picker`。正式持久化目标是 **SQLite + Drift 的事务化存档**，目前**尚未实现**。

## 2. 已验收事实（按时间顺序）

| 里程碑 | 证据与准确边界 |
|---|---|
| 历史原型 | 用户手机曾完成 **8/8** 项验证；不触碰旧版原型应用与数据。 |
| V0.1b 引擎/界面 | GitHub Actions [38141798593](https://github.com/54854434/terminal_x/actions/runs/38141798593) 中 **17/17** 项测试、APK 构建通过；用户手机完成 **10/10** 项交易/恢复验收（市价买卖、拒单、冻结、撤单、跨档部分成交、步进和重启等）。这不代表长时间或异常断电测试已做。 |
| V0.1b 原始备份 | 用户通过 Android Termux、无线 ADB、`run-as com.terminalx.preview.terminal_x` 只读取得 `shared_prefs/FlutterSharedPreferences.xml`，大小 **432850 字节**。复制为 Termux 私有 `~/terminal_x_v01b_backup.xml`；与源文件 **SHA-256 相等**（`BACKUP VERIFIED`）；在手机 Download 另存第二份且 `cmp` 一致（`DOWNLOAD BACKUP VERIFIED`）。用户执行 Python 检查得到 `SNAPSHOT FORMAT OK`、`ENGINE STRUCTURE OK`。这些是用户手机反馈，不代表助手接触过私有 XML。 |
| V0.1c 签名路线 | 旧版 V0.1b APK 包名 `com.terminalx.preview.terminal_x`。修正签名诊断 [38146867761](https://github.com/54854434/terminal_x/actions/runs/38146867761) 显示临时 debug 签名证书与已验收 V0.1b **不同**；因此不走同包名覆盖安装。V0.1c 改为**独立包名** `com.terminalx.v01c.terminal_x`，新旧应用并存。 |
| V0.1c 第一阶段 | `lib/engine/tx_backup_import.dart` 加入 Android XML 精确键读取、拒绝缺失/重复/损坏数据、`TxSession.importJson()` 和 `engine.checkInvariants()`；增加八项 XML 只读导入测试；用户已上传 GitHub。 |
| V0.1c 第二阶段 | `lib/main.dart` 加入手机选 XML、账户/订单/成交预览、明确确认导入；`lib/engine/tx_backup_commit.dart` 在新 App 自身私有数据区先保留导入前会话，再一次性导入并校验，防止重复导入；另有四项提交保护测试。用户已上传 GitHub。 |
| V0.1c 首次构建故障 | [Actions 38153917320 / job 114512843355](https://github.com/54854434/terminal_x/actions/runs/38153917320/job/114512843355) 日志：**29 项测试全部通过**，但 `file_picker 8.3.7` 的 Android `compileSdk 34` 与要求 API 36 的插件依赖冲突，APK 构建失败；不是交易或备份引擎测试失败。 |
| 修复与构建 | 将 `pubspec.yaml` 依赖固定为 `file_picker: 10.3.10`，最新提交 `21e68a5f8edcfc1653bd1da86ac9553ab09f0416`；用户反馈最新 **Build Terminal X V0.1c (isolated APK)** 显示**绿色**。此次对话核对了代码及工作流，未取得该次绿色运行的具体 run ID；后续如需精确证据再查询。 |
| **V0.1c 实机迁移成功** | 用户安装了独立 V0.1c，选取 Download 的旧 XML，**看到了预览、确认预览与备份时数据一致、点击确认导入成功，并完全关闭应用后重新打开，数据仍然一致**。截至 2026-10-12 该项由用户明确验收通过。**导入后的新增买卖/撤单/步进回归尚未执行**。 |

**注意**：第一次 Python 校验只代表结构正确；真正的账务约束验证发生在 V0.1c Dart 引擎预览/导入阶段。实机成功不等于已经实现 SQLite 原子事务，也不等于新版本再升级时可保留数据。

## 3. 当前仓库与关键实现

- **HEAD**：`21e68a5f8edcfc1653bd1da86ac9553ab09f0416`（2026-10-12 核实）。
- **主应用**：`lib/main.dart`，标题 `TERMINAL X · V0.1c`，文件选择/预览/导入 UI 与已有交易 UI 同页；交易异步存盘采用 `_writeChain` 串行，导入时暂停交易并等待待存盘请求。
- **核心引擎/会话**：`lib/engine/tx_engine.dart`、`lib/engine/tx_session.dart`；`TxSession.saveKey='terminal_x_v01b_state'`，原型旧键 `terminal_state`；会话快照 schema 1，内含引擎快照与历史账务。与旧版应用共享的是**格式**，不是应用私有沙盒。
- **导入校验**：`lib/engine/tx_backup_import.dart`；解析 Android preferences XML 中 `flutter.terminal_x_v01b_state` 或无前缀的对应键，调用 `TxSession.importJson` 和引擎不变量检查，失败拒绝导入。
- **保护写入**：`lib/engine/tx_backup_commit.dart`；新 App 导入前旧会话副本键 `terminal_x_v01c_pre_import_state`；一次性锁定、重复导入拒绝、失败保护。**仍基于 SharedPreferences，两个键写入不是数据库原子事务**。
- **测试**：`test/tx_engine_test.dart`、`test/tx_session_test.dart`（含 XML 校验测试）、`test/tx_backup_commit_test.dart`。失败的首次构建日志明确显示 **29 个测试通过**。
- **依赖版本**：`pubspec.yaml` 中 `version: 0.1.1+2`、`shared_preferences: ^2.5.3`、`xml: ^6.5.0`、`file_picker: 10.3.10`。
- **构建**：`.github/workflows/build-apk.yml` 工作流名称 `Build Terminal X V0.1c (isolated APK)`；先执行三套 `flutter test`，再 `flutter build apk --debug`；用 `flutter create --org com.terminalx.v01c --project-name terminal_x --platforms=android .` 生成独立 App，校验 `applicationId`/`namespace`，产物 Artifact `terminal-x-v01c-isolated-test-apk`。
- **规范交接**：`docs/TERMINAL_X_HANDOFF.md` 当前远端 v2.6 **滞后于本文件**，暂不要求用户立刻重复上传；新会话不应据此回退到“尚未备份/尚未导入”的旧状态。既往清理的七个冗余 ZIP/工作流/MD 已完成，无须重做。

## 4. 数据、升级和隐私安全底线

1. 用户旧 App `com.terminalx.preview.terminal_x` 与新 App `com.terminalx.v01c.terminal_x` **相互隔离、同时保留**；不要以任何同包名或未知证书的新 APK 覆盖旧 V0.1b。
2. 保留原始手机 App 数据、Termux 私有 XML 副本和 Download 备份。Download XML **未加密**，勿向聊天、云端公开链接或 GitHub Public 仓库上传；迁移成功不等于可以删除备份。
3. V0.1c 导入后已有新的私有存档。未来继续开发/安装新 V0.1c APK 时，必须核实**相同签名与更高 versionCode**，否则不能直接假定可原地升级。GitHub Actions debug keystore 通常不宜作为稳定发布签名。
4. 需要在 Drift/SQLite 中设计明确的 schema、事务、版本升级、一次性迁移、幂等与失败恢复；保存资产、冻结、委托、成交和账本校验。避免重复写入、半写入、意外新账户覆盖旧账户。安全备份/导出能力也应规划为 App 内功能，不能长期依赖无线 ADB。
5. 任何测试不应要求卸载旧版或清除数据。交易回归测试会改变新 V0.1c 模拟账户，测试前记录当前状态并意识到 Download 中原始 XML 仍是**导入时快照**，不是后来交易的最新状态。

## 5. 下一阶段的唯一优先任务及验收标准

**A. 首先完成 V0.1c 迁移后的交易回归（手机实测）**：

- 启动新 V0.1c 并确认导入的数据仍存在；记下或本地截图当前模拟时间、现金、持仓、开放委托数（不需要把数据发给助手）。
- 选择适当小额/小股数，分别验证**买入、卖出、资金不足/无持仓拒单、限价买单冻结与撤销、限价卖单冻结与撤销、行情步进、部分成交/滑点**。应以用户当前账户实际可用资源和有限盘口为准，不盲目承诺每笔都会成交；严格核对资金/库存及冻结变化。
- 完全关闭后重启新 V0.1c，确认现金、持仓、订单、成交、冻结和步进时间保存一致。**未完成前不能把交易回归标记为已通过**。必要时基于已有交易引擎测试额外补充回归用例。

**B. 回归通过后推进 SQLite + Drift 持久化**：先制定不覆盖当前 `shared_preferences` 会话的双读/只读迁移设计、事务提交和校验门禁；使用可控的测试数据与故障注入验证备份、回滚、重复迁移和异常退出，再做 APK/手机验收。先解决稳定签名与以后 V0.1c 更新策略，再让用户在已有真实模拟存档上试升级。

**C. 文档维护**：到下一重大里程碑或明确要求交接时，覆盖更新同一份 MD，记录最新 SHA、测试、运行 ID、手机验收、风险和下一任务；**不要频繁要求手机手工同步**。

---

**新对话第一句可用**：请按 Terminal X v3.2 交接继续。V0.1c 已在 Android 真机成功从 V0.1b XML 导入并在完全关闭重启后保持数据一致；当前做迁移后交易回归，再规划 SQLite/Drift。只有安卓手机，旧 V0.1b 和双份备份必须保留；先核对 GitHub 最新仓库，不要重做备份或把迁移当成未完成。 
