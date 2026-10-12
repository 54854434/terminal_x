# Terminal X｜唯一持续交接文档

> **交接稿 v3.9.1｜2026-10-12，待 GitHub 自动整合。** 当前远端 `main` 最新已核实 `6f528952905f4ec89c0e1a2fcf8a8be11365abaf`（提交删除 `docs/V01B_MOBILE_UPGRADE.md`）；远端本文件目前为 v3.7。此稿只能在新的单 ZIP **完成 GitHub Actions 通过并成功提交后**才算已入库。  
> **仓库**：https://github.com/54854434/terminal_x ；**唯一规范交接位置**：`docs/TERMINAL_X_HANDOFF.md`。  
> **本批状态**：首次新版 Actions `38185271764` 失败，失败点为 ZIP 清理清单仍要求删除已从仓库移除的 `docs/V01B_MOBILE_UPGRADE.md`；失败发生在 ZIP 校验，Flutter 测试、签名及 APK 均未启动，其他待删文件未变。本 v3.9.1 修复 ZIP **只移除了不存在文件的清理条目**，保留同样的产品源码和 0.2.3+23 版本；修复包仍待重新运行 Actions 和手机实测。此文档的路线图是可随实测、玩法反馈和架构变化重新编写的工作计划，并非永久不可修改的产品规范。

## 1. 不变的安全与协作要求

- 用户**只有 Android 手机，没有 PC**；通过手机 GitHub 网站上传；后续日常一次只上传一个根目录 `terminal_x_batch.zip`，无需逐个上传源码文件。`.github/workflows/tx-batch-import.yml` 是此交付协议的一次性引导文件，升级它需要额外单独上传一次。
- 开发顺序：批量功能开发 → 自动测试和账务回归 → Android APK 构建 → 一次提交 → 里程碑集中手机验收。**不重复以前已通过的旧实机测试**。仍必须跑必要的自动回归。
- 过去已实测的 V0.1b/V0.1c 旧应用、Termux 与 Download 私人备份以及旧 XML 不可删、不可改、不可公开上传。不同包名的 V0.2/V0.2.1 试玩存档也保持不动。不得清理 Android 用户实际存档来释放空间。
- SQLite 数据或 SHA/账本校验失败必须停止交易，绝不自动清空、重置或用伪造新账户代替；所有 NPC 必须有真实有限现金/持仓，真实成交量只能从实际撮合产生。
- GitHub 连接权限 `pull=true, push=false`：助手只能核对和生成交付包，不能自行推送。不得把私钥、凭据或私人交易存档放入 Public 仓库、ZIP 或交接文档。

## 2. 已证实的产品进度

- V0.1b：历史引擎回归、Android 真机与 XML 备份校验通过；V0.1c：独立包名、XML 只读导入及真机买卖/冻结撤单恢复通过；V0.1d：独立 SQLite 跨重启探针通过。这些是历史里程碑，无需每次重测。
- V0.2：批量 Actions `38164243179` 自动测试及 APK 通过；用户 Android **6/6** 基础交易与持久化验收通过，但指出 K 线变化不足、模拟时间设计不合理、长时间倍速卡顿。
- V0.2.1：Actions `38167228004` 测试、APK 与 Artifact 清理 Job 均通过；用户安装并截图确认时钟和参考价格可见，但 K 线多为横条、没有活跃 NPC、没玩家时缺少真实成交量，**市场玩法未通过**；连续长时间稳定性未获通过证明。
- V0.2.2：前一轮已在本地制作包含 4 个真实账户 NPC、市场逐笔及 OHLC 改进的 ZIP，但 **截至最新 GitHub 检查没有上传与 CI 运行**。不再要求上传旧 V0.2.2 包；其内容已经并入本轮准备的统一发布线。

## 3. 用户本轮新要求及对应策略

用户明确提出：APK 尽量缩小；GitHub Code 中 `lib/`、`test/`、`.github/workflows/` 清理过时文件；**交接文档中的产品内容和开发方向每版都可以优化、删改、重排**；游戏时间应模拟 24 小时制并按现实每 1 秒为计时节拍，1×=1 游戏秒、N×=N 游戏秒，更多速度；应用桌面名称恒定为 **Terminal X**，版本号独立递增，长期支持在 Android 上**覆盖更新且不丢失已保存账户**。

实现原则：

1. **统一发行线**：从本次新版本 `0.2.3+23` 开始 Android 包名固定 `com.terminalx.game.terminal_x`，展示名称 `Terminal X`；未来只提高 `versionName/versionCode`，保留同一包名。此版本**首次仍需单独安装**，无法把现有 V0.2.1（`com.terminalx.v021.terminal_x`）跨包名覆盖；两个应用数据保持隔离。之后用同一稳定私钥签名才可同包名升级。
2. **签名是硬性要求**：Release keystore 由用户在手机本地安全生成和备份，通过 GitHub repository Actions Secrets `TX_RELEASE_KEYSTORE_B64`, `TX_STORE_PASSWORD`, `TX_KEY_PASSWORD`, `TX_KEY_ALIAS` 一次配置。新版导入工作流缺任何密钥即失败，**绝不静默回退临时 Debug 签名**。密钥或密码不得公开上传。
3. **缩小包体**：新批改为 `flutter build apk --release --split-per-abi --target-platform android-arm64`，上传单一 `app-arm64-v8a-release.apk`；Debug APK 83 MB 是先前 Artifact 体积（不等同 APK 本体），实际 Release 大小需以新 Actions 构建日志为准。ARM64 APK 仅适用于 64 位 ARM 手机，其他 ABI 未来按需单独生成。
4. **连续秒钟**：从模拟第 1 天 09:30:00 开始，UI 使用精确 `HH:mm:ss`；自动运行每 1 个现实秒添加速度倍率对应的游戏秒。速度 `1×/2×/5×/10×/15×/30×/60×`，最多每秒只跨越 1 个完整游戏分钟，因此最多每秒 1 次 SQLite 市场提交。设备慢时暂停计时等待提交，**不追补或跳过尚未提交的市场分钟**。停止运行/后台暂停；单次仍保留最多 60 个已提交市场分钟保护上限。
5. **秒的持久化边界**：当前 SQLite 只持久化完整游戏分钟，秒内 UI 进度是前台临时显示；关闭应用后仍恢复最后一个已提交的游戏分钟，秒数重新从 `:00` 开始。**此项不是秒级完整持久化**，在后续版本设计安全的秒进度存储，不得为了每秒落库而恢复卡顿。
6. **市场博弈**：引入 4 个有限资金和库存 NPC，真实下单、互相和玩家撮合，内存增量 K 线和“市场逐笔”。算法是确定性的模拟规则，不伪称真实 AI/真实投资。
7. **精确安全清理**：新版导入 workflow 仅允许带旧文件 SHA-256 的清单删除已确认废弃的 `lib/main_terminal_v02.dart`, `lib/main_terminal_v021.dart`, `lib/storage_probe_main.dart`, 2 个一字节占位 `lib/market/test`, `lib/widgets/test` 和废弃旧指引 `docs/V01B_MOBILE_UPGRADE.md`；新版 `lib/main.dart` 变成统一入口。全部回归、签名版 Release 构建完成后才提交删除。**不清理**任何仍在 `test/` 中的账务、SQLite、备份回归，旧版本由 Git 历史保留。
8. **工作流文件处理**：在成功发布后，具有 `actions:write` 的专用 job 会尝试**禁用** 5 个已废弃的历史构建工作流（可逆，历史记录保留），避免每次上传跑多次无用 APK；**不会自动从 Code 删除 `.github/workflows/*.yml`**。GITHUB_TOKEN 不能被假定具有修改工作流文件的权限；以后如需彻底删除 YAML 文件，需用户安全地手动审核并提交或明确授予有权限的凭据（目前不要求 PAT）。现有批量进口工作流必须保留。
9. **自动清理 GitHub Artifacts**：仍遵守已建立的旧 Debug Artifact 清理与 30 天自动过期策略；新的签名 Release Artifact 不在旧 Debug 清理规则内，保留最近构建供下载，除 GitHub 自动过期外不可直接扫除最新有效发布产物。

## 4. 本轮批量文件与验证范围

需要先由用户覆盖 `.github/workflows/tx-batch-import.yml` 一次（添加 release signing/arm64/安全源码清理/禁用旧 workflow）；再在 GitHub Settings → Secrets and variables → Actions 设置 4 个私密签名项；之后上传 **唯一** `terminal_x_batch.zip` 到 `main` 根目录。

ZIP 的核心代码：`lib/main_terminal_v023.dart`、`lib/market/tx_realtime_clock.dart`、`lib/market/tx_npc_market.dart`、`lib/market/tx_candle_history.dart`、`lib/engine/tx_session.dart`、`lib/storage/tx_trading_service.dart`、`test/tx_background_market_test.dart`、`test/tx_realtime_clock_test.dart`、`lib/main.dart`、`pubspec.yaml`、本交接 MD。项目已有 `lib/market/tx_live_candles.dart`、`lib/market/tx_simulation_clock.dart`、`lib/storage/tx_sqlite_store.dart` 和旧回归测试继续保留。

提交前自动跑旧引擎与 SQLite、成交量及 NPC 真实撮合、增量 K 线、秒钟跨日/倍率/错误速度、数据守恒与 APK release 签名校验。**本地没有 Flutter/Dart SDK，不能把静态清单校验当作编译或手机实测。**

## 5. 未来可调整的玩法路线图

以下为**当前建议，不是永久约束**：

- **近期**：先取得稳定可覆盖升级的小体积 APK、可持续运行的市场和游戏秒钟。观察玩家反馈及具体手机性能；仍需研究持久化记录规模增长、长时运行、跨版本 SQLite schema 迁移（必须无损或拒绝）。
- **随后**：交易前成本/滑点预估、已实现和浮动收益、持仓成本、总资金、实际可清算净值与回撤，让模拟大资金操盘有明确反馈。
- **再后**：交易模式、市场时段与日历（当前 24h 连续开放是沙盘模型，不是假装已经实现 A 股交易制度）、多类非均质 NPC、期限/清算、自由沙盘和可选任务挑战。资产、市场、投资玩法应依据实际体验灵活调整、拆分或删掉未证明有价值的方向。
- **长期性能与存档**：逐步用结构化成交流/紧凑检查点替代每步完整 JSON 快照，兼顾历史 OHLC、账务完整与崩溃恢复；在数据库兼容和签名确定前**禁止自动删除玩家历史**。

## 6. 下一步验收与交付事实

目前远端最新为 `6f528952`，当前根目录旧 ZIP 已经上传，但首次 Actions 因清理清单引用已不存在的文档而失败；**新版 workflow 已在远端，无需再上传**。修复后的本 ZIP 应直接覆盖根目录同名 `terminal_x_batch.zip` 并提交，自动触发新运行（若上传后没有触发则手动 Run workflow）；不要只是重新运行旧文件的失败工作流。四项签名 Secrets 是否配置正确尚未通过该轮验证，不要提前宣称签名成功。CI 通过后优先检查 Release ARM64 APK 体积、同包名/签名/版本、1× 现实秒钟、倍率提升、单分钟真实 NPC 成交、长时间 SQLite 性能。覆盖升级的完整验证必须等下一个 `0.2.4+24` 版与本版共享签名时才能证明；当前安装 `0.2.3+23` 不等于“已经证明覆盖成功”。

**新对话简短交接语**：按 Terminal X v3.9.1 继续；过去 V0.2 实机 6/6 基础通过、V0.2.1 Actions 成功但市场缺少 NPC。此轮新 workflow 已上传，原批量运行 `38185271764` 因过期文档清理清单失败，v3.9.1 ZIP 已移除该条、待运行；把未上 GitHub 的 V0.2.2 NPC 功能并入 `0.2.3+23` 稳定发行线，Release ARM64/固定包名/游戏按秒计时、速度 1–60×、SHA 安全清理旧源码和禁用老工作流，日常单 ZIP；切勿声称 CI 已通过或覆盖更新已验证。
