# Terminal X｜唯一持续交接文档 v7.0（V0.2.9 首批 GitHub 编译候选）

**更新：2026-10-12。重要：这是随导入 ZIP 同步更新的交接文件，不能再拿旧 v4.9 / v6.0 当作最新状态。**

## 1. 仓库、版本、真实状态

- 仓库：https://github.com/54854434/terminal_x；GitHub `main` 在本批准备时为 `8e1bee83dc59d5167ff5d05accdd3431d7e15aed`（上一个已取消上传 ZIP 的删除提交）；其正式 V0.2.8 核心源文件仍对应 `ff21c10b8be3ac1926ff396440917b64700548a6`。实际导入时必须重新核查远端，以每个文件的 `previous_sha256` 为并发保护。
- **最后已发布并有成功 CI 的版本：V0.2.8 / `pubspec.yaml` 0.2.8+28。** 本批为 `V0.2.9+29` 未经 Flutter 编译的 CI 候选；绝不能称已发布、可覆盖安装或高倍率已实测。
- 之前的上传尝试：Actions `38235906465` 已取消；`38236033943` 在“Verify ZIP manifest and stage source changes”阶段失败；`38236229707` 发布工作流 skipped。这些不能当作 Flutter 编译失败或通过。已取消的旧 ZIP 不能继续复用。
- 用户授权由开发助手自主决定引擎、UI、SQLite、甚至底层语言和测试时机；但必须每轮交付同时更新交接文档和真实进度，不再无限堆积未入库实验 ZIP。

## 2. 产品和绝对安全边界

Terminal X 是完全离线的 Android 虚拟交易游戏，无真实资金。目标长期包括 A 股、美股、期货、外汇、加密货币五类市场、有限资产 NPC、真实订单簿及统一风险账簿。保留深蓝黑视觉、青绿 X 品牌，不复制第三方交易所素材。

不可变约束：Android applicationId `com.terminalx.game.terminal_x`、应用名 Terminal X、与 V0.2.8 同一发布签名、versionCode 只能递增、原私有 SQLite 与备份不得卸载/清空、资金/库存/冻结/订单/Fill/Ledger 必须平衡，错误或不确定写入要拒绝进一步交易。K 线只来自已提交报价与真实 Fill，不伪造成交、数量或影线。

## 3. 本批 V0.2.9+29 实际包含的文件和行为

- `pubspec.yaml`：0.2.9+29。
- **实际已有代码路径优化**：`lib/market/tx_live_candles.dart`。保留原来最多 1500 根 K 线及 schema 1；对已提交、没有新 Fill、市场价格未变且同游戏分钟的挂单/撤单修订，直接保留旧 K 线对象，避免不必要的快照对比与渲染失效。任何真正推进游戏分钟的提交仍生成 K 线；成交历史计数回退则停止处理。
- **已开发、未接入当前主界面的可复用模块**：`lib/market/tx_continuous_flow_clock.dart`（帧时钟、一分钟单事务闸门、即时暂停、100×/120× 候选、360000× 模型上限，实际吞吐由持久化限制）；`lib/market/tx_speed_feedback.dart`（显示周期建议、已提交分钟计算实际倍速、固定容量样本和事务闸门）。**新增模块不等于正式主界面已有 100×、600×、3600×。**
- Flutter 回归新增 `test/tx_live_candles_fastpath_test.dart`、`test/tx_continuous_flow_clock_test.dart`、`test/tx_speed_feedback_test.dart`；连同正式旧版 20 个活动 `tx_*_test.dart`，导入 CI 必须运行完整 23 项文件。新增测试未在本机执行。
- 本文件和 `scripts/tx_release_notes_zh.md` 同步进入 ZIP。**这是实际运行快路径优化 + 安全的研发模块移交，不是完整 V0.2.9 性能重构。**

## 4. 已积累、尚未纳入生产的研发工作（历史第 1～9 轮）

- 帧驱动空心指示 K 线、Ticker 渲染隔离、忙碌事务期间即时暂停、100×/120× 候选显示；每真实秒推进 100 个**游戏秒**，不是每秒生成 100 根 1m K。
- 扩展 600×/3600×/36000×/360000× 的观察周期选择、达成倍速测量；**高倍率多分钟原子交易和整条真实经济事件流尚未接入生产**。
- 实验性 Journal：逐分钟交易增量、SHA-256 链、定期检查点、1～16 分钟原子提交、成交派生 OHLCV 与独立分钟索引、老历史冷启动覆盖扫描及完整性检查。**不能将实验独立 Journal DB 直接覆盖/迁移生产 `terminal_x_game.sqlite`。** 全历史哈希、重放和 JSON 工作仍可能 O(历史长度)。
- 研发目录已有 156 项 Python/SQLite 测试通过（第九轮）；这些是独立 Python/合成合同验证，既不代表 Dart 通过，也不是 Android 实机跑分。上一轮研发材料：`terminal_x_dev_progress_20261012_r9.zip`（独立研发归档，不能导入 GitHub 工作流）。
- 还有一个严格按已发布 V0.2.8 旧文件 Git blob 哈希检查的组合候选生成器 `assemble_v029_flow_chart.py`，可在有干净 checkout 的环境上生成性能+时钟+图表叠加代码。**这一组合候选未完成真实 Flutter 编译，不能跳过 CI、旧档测试而直接部署。**

## 5. 交付与 GitHub 操作：务必沿用已成功的旧流程

1. 开发助手生成根目录唯一 `terminal_x_batch.zip`，其中包含 `manifest.json` schema=1，每个加入的文件 SHA-256 校验、旧文件的 `previous_sha256`、Android 身份与递增 versionCode、以及**仓库所有活动 `tx_*_test.dart` 测试列表**。
2. 用户把 ZIP 上传至 https://github.com/54854434/terminal_x 的 `main` 根目录，触发 `Terminal X - One ZIP Verified ARM64 Release`。不重复上传 YAML/图标，不把独立研发资料 ZIP 当导入包。
3. 导入工作流先按文件哈希检查冲突、运行全部 Flutter 测试、构建 ARM64 签名 APK、验证 APK 签名；全部成功才提交源码、删除 ZIP，然后后续工作流可能自动发布 Release。
4. GitHub 失败时先定位失败步骤：导入/路径与哈希失败、Dart 编译失败、Flutter 测试失败、签名或 APK 构建失败。只修复真实失败，不虚报通过。如果远端版本先改变，**停止沿用旧 previous_sha256，重新构造 ZIP**。
5. 签名构建成功后还需验证签名证书与旧 V0.2.8 相同（历史已知 SHA-256：`9e241239e993fb4352e2e05fb0f134774ec60ecd826b749f93d0be76cb1c8699`）；如不一致，不能让用户卸载旧版以解决冲突。
6. 测试时机不需重大版本完成，但手机测试前必须有可用 APK、旧数据安全证据、清楚的测试范围；旧 SQLite 原地覆盖安装、账户/持仓/订单/Ledger 对账、冷启动、1×～60× 及新倍率正确性、模拟分钟连续性、暂停和长期运行性能都要验收。

## 6. 发布门槛及工程进度

- 截止此文档编写时：**V0.2.9 发布/实机验收进度约 30%（粗估）；Flutter 编译 0 次已确认；签名构建 0 次已确认；Android 实机测试 0 次。** 不能因为 156 项 Python 检查或有研发 ZIP 就增加交付百分比。
- 此候选导入后如果 CI 通过，仍只证明运行快路径及独立模块编译，不证明 100× 真正启动或根治旧 SQLite 性能热点。
- 最高优先级：取得首次真实 GitHub Flutter 诊断 → 修复编译 → 分批整合已准备的主界面连续 K 线/性能 patch → 真正将游戏分钟批量事务及事件驱动真实价格形成移入生产 → 旧档/长时间运行/签名验收。

**每次后续生成导入 ZIP，必须同步更新此文件和中文发布说明，不允许重复遗漏。**
