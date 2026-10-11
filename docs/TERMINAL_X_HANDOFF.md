# Terminal X｜唯一持续交接文件

> **文档版本**：v2.6（精简重构）｜**更新日期**：2026-10-11  
> **仓库**：https://github.com/54854434/terminal_x（Public，`main`）  
> **唯一规范文件**：`docs/TERMINAL_X_HANDOFF.md`  
> **最近核实的 `main` HEAD**：`c59c4fba294c7b42181bcae51bd9bd810c2ed479`（清理完成）  
> **远端规范文件版本**：v2.4，Git blob `0eab48d5f3e3e95a118f96352307243ca0de55f1`；**本 v2.6 仅已生成，尚未推送**。上传前重新查 HEAD/版本，不覆盖更新版本。  
> **当前唯一优先方向**：保护已实测通过的 V0.1b，准备 V0.1c 安全存档迁移（先确定 APK 签名、升级与备份方案）。

## 0. 长期工作协议（每次新会话均执行）

1. **用户只有安卓手机**，不使用电脑；开发操作以手机浏览器 GitHub、GitHub Actions 云端 Flutter 测试及 APK 构建为前提。仓库连接目前 `pull=true`、`push=false`；不可假称替用户提交。手机步骤须给出准确路径、文件名、操作方式和验收标准。不要求安装插件、提供 PAT/密码。
2. **先核对最新事实再行动**：读取 GitHub `main` SHA、规范交接文件、相关源码/工作流与 Actions；新提交优先于本文旧记录，不可用旧文档覆盖更新进度。分清“用户手机已实测 / GitHub 自动测试通过 / 构建成功但未实测 / 仅计划或待验证”。绝不虚构通过项。
3. **交易一致性优先**：撮合须价格优先、同价 FIFO；资产、冻结、订单、成交流水和做市商库存守恒；大单通过有限盘口成交影响滑点，不提供直接拉价按钮。先测试再构建 APK，最后手机实测；不为追求功能数量破坏最小闭环。
4. **唯一交接、禁止堆叠冗余**：仅维护 `docs/TERMINAL_X_HANDOFF.md`。每次更新**替换当前状态、构建、风险、下一步等既有章节**，不要逐次追加“v2.x 最新状态”历史长章节；旧过程用 commit / Actions 链接追溯。避免重复规则、过时的“尚未实测/待清理”、时间戳副本和 `LATEST` 副本；合理目标是简洁完整（非硬性字数限制）。
5. **每次开发/清理里程碑结束必更新 MD**：记录版本/日期、主分支 SHA、变动路径、最新确认 APK 构建/签名、自动测试和手机验收、未解决问题、唯一下一任务与验收。生成文件须提供下载，明确“未提交 GitHub”状态；用户提交后再查文件路径和正文版本。
6. **安全与回退**：私人手机存档、Token、密码、签名私钥不得上传 Public 仓库；不卸载已验收 App，不清除数据，不以临时 debug APK 假定可稳定覆盖升级。删除必须有清单与确认、只对明确路径操作；保留测试、代码、构建工作流和 Git 历史。不承诺后台自动开发或同步。
7. **用户触发语**“整理项目进度 / 生成最新交接MD / 准备切换新对话”必须在当次对话生成完整可下载 Markdown；接收新交接后直接推进下一件可验证工作，不重写空泛策划案。

## 1. 产品边界与不可变决策

- **产品**：Terminal X，安卓独立离线、单人自用、专业交易终端风格的金融交易及大资金操盘模拟器；不是剧情、社交或真钱交易 App。不要引入真实券商下单、账户服务器或云端大模型作为早期依赖。
- **分阶段范围**：V0.1 先做两只虚拟股票，分别体现高/低流动性；长期支持 A 股、美股、期货、外汇、加密资产五大市场，市场/品种规则独立配置，包括时段、T+1/T+0、费用、结算、涨跌停、杠杆、保证金、强平、汇率等；尚未实现不得称已实现。
- **模拟机制**：统一真实虚拟订单簿、有资金/库存约束的本地交易员或做市商、限价/市价单、部分成交、撤单及冻结、大单跨档滑点和退出成本；影响取决于相对流动性而非固定资金门槛。生成市场可受订单影响；历史真实价格回放不能被玩家交易篡改。
- **时间和界面**：时间无限延续、可配置初始日期/速度/暂停/步进/分支存档；手机竖屏深色专业 UI，未来交互 K 线、全屏图表、盘口、成交、持仓、风控、TWAP/VWAP 等。现阶段只实现一部分。
- **技术**：Flutter/Dart；正式持久化规划 SQLite + Drift；先用本地有限规则策略，不预设 Rust、联网或复杂 AI。用户手机操作 GitHub Actions 云端构建 Android APK。

## 2. 经验证的当前里程碑（2026-10-11）

| 范围 | 真实状态 | 证据/界限 |
|---|---|---|
| 旧版原型 | **用户手机 8/8 项通过** | 历史 APK；保留旧 App 与存档 |
| V0.1b 引擎 | **已入库；17/17 自动测试通过** | `49836dacb90819e653fadc3bbed47d43c2c2fb83`；Actions [#38139622283](https://github.com/54854434/terminal_x/actions/runs/38139622283) |
| V0.1b Flutter UI | **已入库** | 代码里程碑 `290fbf66605f6e0b9df5d72b3aab51d2b72c44d5` |
| V0.1b APK | **GitHub 构建并上传成功** | Actions [#38141798593](https://github.com/54854434/terminal_x/actions/runs/38141798593)，job `114476989497`，17/17 测试 + debug APK |
| V0.1b 手机验证 | **用户反馈 10/10 通过，无异常** | 安装/初始账户与双股票/市价买卖/资金不足与无股拒单/买入资金冻结与撤单/卖出持仓冻结/跨档部分成交/行情推进与重启恢复；不等于压力/断电测试 |
| GitHub 整理 | **7/7 项已删除、逐项 404 确认** | 最新清理 `main` SHA `c59c4fba294c7b42181bcae51bd9bd810c2ed479`；详见 §4 |
| 整体 V0.1 | **未全部完成** | SQLite、固定签名、交互 K 线、自动倍速等仍待做 |

**当前源码特征（已核实，非完整功能清单）**：`lib/main.dart` 使用 `TxSession`/`TxEngine`；`lib/engine/tx_engine.dart` 实现整数分账务、双侧订单簿、有限撮合、冻结与撤销、快照校验；`lib/engine/tx_session.dart` 提供 `SIM-A01`/`SIM-A02`、有限资金库存流动性提供者、可复现步进；`test/tx_engine_test.dart` 与 `test/tx_session_test.dart` 目前共 17 项。存档在 `shared_preferences` 的 `terminal_x_v01b_state`，旧原型为 `terminal_state`；旧挂单迁移仅归档，读取坏存档保护停交易。**顺序写盘不等于 ACID 原子事务。**

**APK 与签名**：已确认 Artifact [#11702639474](https://github.com/54854434/terminal_x/actions/runs/38141798593/artifacts/11702639474)，名称 `terminal-x-v01b-stage-b-preview-debug`。ZIP 工件 SHA-256 `6115d744cd32527897f678b11ee1011a7ecf2cc1b99f54203c2e8e8d314e24f6`，**不是 APK 单文件摘要**。构建命令 `flutter create --org com.terminalx.preview --project-name terminal_x --platforms=android .`，预期应用 ID `com.terminalx.preview.terminal_x`；实际证书指纹、稳定覆盖升级兼容与 APK 单文件 SHA 待核实。最新成功 Actions **仅指已核实的上述运行**，本次清理提交可能触发其他构建，未逐一核查。

## 3. 保留的关键仓库文件

- `lib/main.dart`；`lib/engine/tx_engine.dart`；`lib/engine/tx_session.dart`
- `test/tx_engine_test.dart`；`test/tx_session_test.dart`；`pubspec.yaml`
- `.github/workflows/build-apk.yml`（测试先于 `flutter build apk --debug`）；`.github/workflows/v01b-engine-validation.yml`
- `docs/TERMINAL_X_HANDOFF.md`（唯一规范交接，远端 v2.4）

本轮核实这些路径在 `main` 均存在，源码/构建主路径未因清理被删除。本轮没有修改 Dart 代码、测试或工作流，也没有主动发起 APK 构建。

## 4. GitHub 清理完成记录（历史索引，不再待清理）

2026-10-11 用户通过手机完成删除；此后逐项从 `main` 读取，下列**七条均 404**；Git 提交记录亦可追溯：

1. `.github/workflows/terminal_x_import_stage_a.yml`
2. `.github/workflows/terminal_x_import_stage_b.yml`
3. `.github/workflows/terminal_x_import_stage_b_recovery.yml`
4. `terminal_x_v01b_stage_A_engine_tests.zip`
5. `terminal_x_v01b_stage_B_bulk_v18.zip`
6. `docs/TERMINAL_X_HANDOFF_LATEST.md`
7. `docs/TERMINAL_X_HANDOFF(20261011-133044).md`

本次清理最新提交：[c59c4fba294c](https://github.com/54854434/terminal_x/commit/c59c4fba294c7b42181bcae51bd9bd810c2ed479)。以上清理**仅删除当前分支路径，不会擦除 Git 提交历史**。以后无须重复计划清理这些文件，除非再出现新的多余文件。

## 5. 未解决风险和后续顺序

1. **升级/数据保护优先**：当前是 Actions 生成的 debug 签名，签名跨构建是否相同未核实；若未来 APK 无法覆盖安装，可能无法直接访问旧 App 的沙盒存档。**在签名连续性、应用 ID、备份/导出方案明确前，不卸载或覆盖已验收的 V0.1b**。目前无已确认 bug；不可凭空重写引擎。
2. **V0.1c 唯一优先开发项：安全持久化**。先验证 Android 安装/签名和现有数据迁移可行性；设计基于 Drift/SQLite 的原子会话快照/交易记录，明确 schema 版本、只读导入 `terminal_x_v01b_state`、旧存档保留、校验、幂等迁移、回滚与失败保护。必要时先增加能在手机端使用的导出/导入能力，才安排真实升级。
3. **门禁**：为迁移和失败注入补充自动化测试（资产、冻结、订单、流水一致性；重复恢复；无效/半写入快照拒绝；升级兼容）；经 Actions 测试和 APK 构建通过后再让用户用手机验证。不得把仅设计或编写的功能记录为已构建。
4. **后续再推进**：稳定签名、初始资金配置、备份与分支、交互 K 线、暂停/多倍速、长期行情与高级 AI/订单执行、五大市场规则。未实施项目都标为计划中。

## 6. 下一次会话的唯一可执行任务与验收

**首先**：将本 v2.6 文档以精确文件名 `TERMINAL_X_HANDOFF.md` 覆盖仓库 `docs/TERMINAL_X_HANDOFF.md`。在手机 GitHub 上传提交页面确认是 **Modified** 该路径，不是新增带日期/`(1)` 的副本；提交后重新读取，核对正文 v2.6 以及新的 `main` SHA。当前连接没有 GitHub 写权限，所以**生成文件不等于已上传**。

**同步后推进**：启动 V0.1c 的第一项技术验证——确认能否安全覆盖升级已安装的 V0.1b APK，以及不丢失现有 `shared_preferences` 存档的备份/迁移路径。先交付可验证的小改动与测试，再考虑 SQLite 实装；任何新 APK 仍先云端测试构建、后手机回归。

**新会话口令**：按本文长期协议继续 Terminal X；先查当前 `main`、主交接版本、工作流和 APK 签名/存档风险；不要恢复已清理工作流；V0.1b 用户已手机实测 10/10；先推进 V0.1c 安全持久化；每个里程碑末**覆盖更新这份唯一交接 MD，而非追加历史全文**。
