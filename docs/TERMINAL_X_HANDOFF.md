# Terminal X｜新对话接续开发交接文档

> **用途**：将本文件上传到新的 ChatGPT 对话，便于直接继续项目，而不必重新讲述全部背景。
>
> **更新日期**：2026-10-11  
> **文档版本**：1.9  
> **当前阶段**：V0.1b 阶段A已在GitHub Actions通过 **17/17** 测试并入库（`49836dacb90819e653fadc3bbed47d43c2c2fb83`）。阶段B用户已上传并运行，run `38140701786` 测试及 **Android APK编译均成功**；但 `git push` 因GitHub App缺少 `workflows` 权限被拒绝，未将新版界面/构建工作流/交接文档提交到 `main`，且本次APK Artifact步骤被跳过。正在准备**手机端两份YAML一次上传**的恢复方式；旧APK保留、阶段B实机尚未验证。完整V0.1尚未完成。

## 0. 新对话给 AI 的指令（优先阅读）

我在开发个人自用的、**仅安卓手机运行**的离线金融交易与大资金操盘模拟器 **Terminal X**。我**只有安卓手机，没有电脑**，请以手机浏览器操作 GitHub、GitHub Actions 云端构建 APK 为前提指导。请先读完整份交接文档，沿用已确定的产品和技术决策，**直接推进下一项可验证的实际开发工作，不要重新写一篇空泛的游戏策划案**。

工作规范：
1. 清楚区分**用户已经确认完成**、**之前生成但未验证**、**计划未来实现**；绝不能把计划说成现有功能。
2. 每一步给出适合手机操作的具体指令、文件路径、完整可复制的内容和验收方法。
3. 优先交付真正能安装、能交易、能保存的最小功能闭环；不要一次堆满五大市场。
4. 新增功能不能破坏资金/订单一致性。先确保测试通过，再构建 APK。
5. 仓库已由用户于2026-10-11设为 Public：`https://github.com/54854434/terminal_x`。允许公开读取真实源码；当前连接仅具有读取权限，**不具备推送权限**，故所有改动必须经手机GitHub手动上传。
6. 每次里程碑结束，**更新本交接文档的“当前状态、下一步、已知问题、文件版本”**，供下一段对话使用。

---

## 0.1 交接文档管理规则（永久生效，供每次新对话执行）

**这不仅是项目介绍，也是项目交接与续开发的工作协议。** 在后续聊天中始终按以下规则执行：

1. **唯一最新版**：以 GitHub 仓库 `docs/TERMINAL_X_HANDOFF.md` 为推荐的长期主文件；新对话用户上传的最新 `.md` 可作为当次交接依据。若仓库文件和附件内容不同，先比较更新时间、版本和最近提交，避免用旧文件覆盖新进度。
2. **明确触发语**：当用户说“整理项目进度”“生成最新交接MD”“准备切换新对话”等，即在**当前对话内**生成一份可下载的完整 Markdown 文件，不能只回复一段文字。平时完成一个可运行的里程碑，也应建议同步更新文档。
3. **新会话开场**：收到交接文档后先阅读全文，确认当前版本、真实已完成事项、未完成任务、仓库路径和构建方式，然后直接开展“下一件唯一优先事项”；不得重复索取文档已有答案或从零重新策划。
4. **每次必更新字段**：文档版本、更新日期、仓库路径/分支/提交SHA（如已知）、APK构建记录与签名状态（如已知）、实测通过项、改动文件与功能、未解决问题、下一步操作及验收标准。未知就标为“待核实”，不可编造。
5. **严格区分进度**：分开注明“用户实测通过”“代码已写但未编译”“构建成功但未实测”“计划中”四类状态。无法独立查看GitHub时，不得声称已检查源码或构建日志。
6. **交付方式**：生成最新版文件后给出下载链接，提醒用户将它上传/覆盖至GitHub相同路径；**生成下载文件不等于已经替用户同步到GitHub**。若已授权并实际使用GitHub工具完成提交，才可以声称已同步，需保留提交信息。
7. **保留连续性**：更新交接文档时保留核心需求、开发限制、技术约束、历史里程碑与关键问题；精简重复叙述，但不能丢失影响后续开发的决策。长期建议在仓库用提交历史追踪，而不是散存多个“最新版”文件。
8. **隐私与安全**：文档及仓库不得包含账户密码、GitHub Token、APK签名私钥、密钥口令或其他秘密；私人应用存档不要上传代码仓库。
9. **不可自动后台执行**：若没有明确启用定时任务或实际GitHub更新操作，不能承诺自行在未来或后台更新交接文件；更新发生在当前用户请求和当前可执行的会话内。

**标准换会话口令：**“请按交接文档继续开发，先核对当前代码状态；本次结束时按照第0.1节维护交接文件。”

---

## 1. 用户已确定的目标和限制

- **产品**：`Terminal X`，专业拟真的全球金融交易模拟器；偏专业交易软件，不做剧情手游。
- **运行设备**：只在**安卓手机**安装运行 APK，不做电脑版；用户目前**没有电脑**。
- **运行方式**：尽量纯离线、单机、个人自用；无需账户、真实券商、交易所下单接口、服务器、联机排行榜或真实资金。
- **市场长期目标**：A股、美股、期货、外汇、加密资产五大市场；各自有正确的交易时间、T+1/T+0相关限制、涨跌停/熔断、手续费、结算、杠杆、保证金、强平、换汇等规则，并允许按市场和品种配置例外。
- **时间**：绝不限定480天；初始日期、模拟持续时间、时间倍速、暂停、逐步推进、存档与分支均可自定义，允许无限期模拟。
- **界面**：尽量接近专业金融交易软件；深色主题、K线与指标、盘口、逐笔成交、自选行情、买卖和挂单面板、持仓、风险指标。为手机竖屏重新布局，K线可横屏全屏。
- **操盘核心**：小资金像普通交易者操作；随着资金规模扩大，可用大额委托、分批执行、批量撤改单、TWAP/VWAP、多策略账户及流动性分析。**玩家买卖通过同一虚拟订单簿实际影响价格和滑点**，不是点击“直接拉升价格”按钮。资金影响取决于**相对市场流动性**，而不是达到固定金额就无条件控盘。必须存在对手方、库存风险、成交限制和退出成本。
- **AI对手**：本地策略交易员/做市商，有独立资金、持仓和风控，可以生成真实虚拟订单，影响盘口和价格；初期不需要云端大模型或强化学习。
- **行情**：第一期以可复现的本地合成市场为主，后期扩展历史行情导入回放、宏观事件、多市场联动和压力测试。历史回放不能被玩家订单篡改真实历史价格；生成式市场允许通过撮合影响价格。
- **明确删减**：剧情、角色养成、任务打卡、社交、多玩家交易、抽卡、真实资金、真实操纵市场功能都不需要。

## 2. 已确定的开发技术路线

| 模块 | 决定 |
|---|---|
| 手机 App | Flutter，目标 Android APK |
| 初版业务逻辑 | Dart，本地撮合与资金计算；只有性能确实需要时才考虑 Rust |
| 本地持久化 | 正式架构使用 SQLite + Drift；更早的极简验证包暂时用 `shared_preferences`，需要迁移 |
| 图表 | 后续评估 Flutter 原生 K 线或 `kline_chart` 等组件；先验证包体积、触控和性能 |
| AI交易员 | Dart 本地规则策略和事件驱动机制 |
| 版本控制 | GitHub **Public** 仓库 `https://github.com/54854434/terminal_x`，默认分支 `main`；当前连接可读不可写 |
| 无电脑编译 | GitHub Actions 执行 `flutter create ...`、依赖安装、测试/分析、`flutter build apk` |
| 本地数据 | 只保存在手机，支持导出/导入备份；不要将私人存档提交到 GitHub |

**开发约束**：用户只能用安卓手机操作网页、编辑文件、上传仓库、查看构建日志、下载并安装 APK。不能给出必须在其本地电脑执行的步骤。云编译不代表 App 运行时需要联网。

## 3. 第一版 V0.1 的实际目标（验收定义）

不要直接一次实现五大市场。第一版只做**两只虚拟股票**：一只流动性较高、一只流动性较低，并且要具备：

1. 深色安卓交易界面：行情、盘口、委托/成交、账户；K线可后续增强，但最终需可交互。
2. 自定义虚拟初始资金；现金、持仓、市值、盈亏显示准确。
3. 市价单、限价单、撤单、部分成交、订单状态和成交历史。
4. 真正一致的**价格优先、同价时间优先**撮合，以及有效买卖盘流动性；大单吃掉多个价位时产生市场冲击/滑点。
5. 模拟做市商/流动性提供者有资金及库存约束，不能无限无条件填单。
6. 简化本地模拟时钟：暂停、手动推进、1x/10x/60x等。
7. 本地自动保存，关闭/重开 App 后资产、订单和模拟状态正确恢复。
8. 自动化测试：余额/持仓一致性、资金不足拒单、部分成交、撤单、订单去重、应用恢复、可复现行情。
9. GitHub Actions 能产出真正可安装的 Android APK。

**阶段性通过标准**：手机能够下单→正确成交→更新余额与持仓→大单影响成交价→退出重启恢复→重新构建安装。不要用静态演示数据冒充真实的虚拟交易结果。

## 4. 已完成的首个手机原型与验收（2026-10-11 用户确认）

用户已经明确确认：
- **用户曾将交接 `.md` 上传GitHub**；已核实 `docs/TERMINAL_X_HANDOFF.md` 后来在提交 `d9b219d` 被删除，主分支目前缺失该路径。用户于2026-10-11已把仓库设为 Public。
- **用户报告安卓APK已生成、安装并可打开**；已确认真实 `main` 的 `lib/main.dart` 为早期简化原型，构建工作流为 debug APK；但旧版APK的具体运行编号、签名证书与对应提交SHA尚未独立核实。
- **8项实机功能测试均报告通过**：
  1. App正常打开，不闪退；
  2. 显示默认100万元虚拟资金；
  3. 两只虚拟股票可以切换；
  4. 买入100股后现金减少、持仓增加；
  5. 卖出50股后资金、持仓相应变化；
  6. 五档盘口及最近成交可查看；
  7. 可以提交、撤销限价挂单；
  8. 退出重进后资产数据保留。

**验收界限**：以上证明基础操作流程正常，**不代表**已实现真实连续订单簿、正确资金冻结、价格-时间优先撮合、可靠多价位价格冲击、手续费、AI持仓约束、完整SQLite账务或专业K线。它仍是可运行的早期原型，不应记为完整 V0.1 验收通过。

此前提供入门包 `terminal_x_mobile_starter.zip`，含：

```text
terminal_x_mobile_starter/
├── pubspec.yaml
├── lib/main.dart
├── .github/workflows/build-apk.yml
└── README.md
```

2026-10-11 已实际读取 `main` 的 `lib/main.dart`：代码仍为 Flutter/Dart + `shared_preferences` 原型，两资产、合成五档盘口、简化市/限价委托、随机推进行情。**已证实旧代码无挂单冻结与连续价格—时间优先撮合**，且随机数无固定种子；不能把新交付未上传的源码说成线上已实现。

### 下一开发目标：V0.1b

1. 引入有状态的买卖订单簿，撮合按价格优先、同价时间优先；成交、盘口深度和挂单数量一致。
2. 提交买单冻结足够资金，卖单冻结可卖持仓；部分成交后按比例释放/占用，撤单释放剩余冻结量；处理无效订单、重复提交及余额不足。
3. 单一事务或等价的一致性机制保存订单、逐笔成交、现金/持仓流水；迁移SQLite/Drift之前规划清楚旧存档升级/导出和签名安全。
4. 最低限度实现模拟做市商的有限流动性；大额单跨多个价位成交时价格与滑点可追溯。谨慎控制手机算力。
5. 添加纯Dart自动化测试，并让 GitHub Actions 在生成APK前执行 `flutter test`。
6. 尽可能保持已经通过测试的8项功能不回退。

**下一项具体任务（2026-10-11 最新）**：阶段A已通过，下一步阶段B：从已交付的 `terminal_x_v01b_stage_B_preview_app.zip` 中仅提取并上传 `lib/main.dart` 和 `.github/workflows/build-apk.yml`（依次在 GitHub 目标目录替换）；`docs/TERMINAL_X_HANDOFF.md` 使用本次最新v1.7，不要使用阶段B ZIP中的旧交接版本。构建动作必须先跑自动化测试再生成独立预览 APK。旧应用保留，避免签名/存档破坏。已核实旧 build #6 成功，详见§13。


### 2026-10-11 私人仓库身份与权限核查（交接版本 1.4）

**当时用户提供仓库地址：** `https://github.com/54854434/terminal_x`。以下404仅为**公开前的历史记录**；本轮已成功读取公开仓库。

**实际执行的 GitHub 连接检查：**

- `get_repo(repository_full_name="54854434/terminal_x")`：GitHub API 返回 `404 Not Found`。
- `fetch_file` 尝试读取 `pubspec.yaml`、`docs/TERMINAL_X_HANDOFF.md`：均返回 `404 Not Found`。
- `list_installations`：`installations: []`；`list_installed_accounts`：`accounts: []`。
- `get_user_login`：连接识别的 GitHub 用户为 **`idx7`**（与用户给出的仓库拥有者 `54854434` 不同）；是否该账户被添加为仓库协作者也未核实。
- `search_installed_repositories_streaming(query="terminal_x")`：结果为空。

**诊断结论：** 当前 GitHub 连接无法读取 `54854434/terminal_x`。这**可能**是连接了不同账号或缺少私仓授权；不能据此断定仓库不存在。未获取默认分支、提交 SHA、实际代码、仓库交接 MD、Actions、构建编号/签名信息；**未修改任何 GitHub 文件、分支或 Actions 设置**。

**历史建议已过期：** 当时仓库仍为Private，曾建议通过插件授权。用户后来主动选择公开仓库，已能读取。不要再要求安装插件或重复核对仓库地址。

**历史检查现状：** 已成功读取前三份真实源码与默认分支、最新提交 SHA；交接文件在最新提交中删除。旧APK Actions运行号与签名证书未能核实。本轮V0.1b源码基于实际原型设计，仍需Actions测试和手机验证。

**本次文件改动：** 只更新会话内 `TERMINAL_X_HANDOFF.md`（v1.3 → v1.4），未更改 `terminal_x_v01b_additive.zip` 中的 Dart/测试/YAML；它们继续保持“已生成未编译、未验证”。本地文件不等于 GitHub 已同步。

### 2026-10-11 本轮增量开发记录（交接版本 1.3）

**审查动作与范围：**已阅读全文上传的交接版本1.2，并尝试通过可用 GitHub 连接查询 `terminal_x` 仓库、可访问仓库清单、GitHub App 安装授权；均无可用目标（安装授权列表为空）。**因此没有检查真实 `main` 源代码，也没有检查任何 Actions 成功记录或构建产物；仓库 URL、分支最新 SHA 和实际工程目录全部待核实。**不应推断 GitHub 上已经接收本次改动。

**本轮只新增旁路文件，绝不覆盖 `lib/main.dart`、`pubspec.yaml`、旧构建工作流或存档：**

- `lib/engine/tx_engine.dart`：零 Flutter 依赖的内存撮合核心：两侧有限订单簿、同价FIFO、按价优先、多档成交价、限价/市价IOC、现金及股票锁定与撤单释放、账户和成交流水、幂等订单ID、自成交防护、JSON快照导出/导入、运行时一致性检查。**状态：代码已写但未编译、未与App连接。**
- `test/tx_engine_test.dart`：11个 `flutter_test` 单测，覆盖价格/时间优先、跨档冲击、有限库存、买卖冻结、撤单、余额不足、ID重复及权限、非法单、自成交、快照恢复/篡改保护。**状态：已写，测试未运行。**
- `.github/workflows/v01b-engine-validation.yml`：新的、与原APK构建解耦的云端测试工作流。**状态：本地文件已生成，未推送，未触发。**
- `docs/V01B_MOBILE_INTEGRATION.md`：手机 GitHub 页面可执行的复制/集成/验收步骤，明确先测试后合并老 APK 工作流，不能未核实就整体覆盖既有YAML。**状态：说明已写。**
- `docs/TERMINAL_X_HANDOFF.md`：本交接文件 v1.3。**状态：会话内生成，可供下载；未推送GitHub。**

**严格的验收边界：**新增引擎不等于用户当前APK启用了该逻辑；`exportJson` 只是序列化，不代表原子写盘/旧存档迁移；在这个执行环境找不到 Dart 和 Flutter 命令，无法运行 `flutter test` 或编译 APK。此前报告通过的8项手机测试**不是针对本次源码的回归测试**。

**下一件唯一优先事项：**找回真实 GitHub 项目路径与构建配置（手机浏览器提供仓库地址/授权或上传 `pubspec.yaml`、`lib/main.dart`、`.github/workflows/build-apk.yml` 和最近一次 Actions 日志），确认它们与现有8项正常App匹配后，先合并三个新增旁路文件并在 Actions 跑11个测试；**测试为绿前不将新引擎接进交易按钮，也不替换旧存档**。随后按 `docs/V01B_MOBILE_INTEGRATION.md` 在原APK工作流的 build 步骤前增加测试门禁，云编译通过后再作接入与手机回归。

**已知问题/风险：**无法校验编译与具体 Flutter API/依赖兼容性；旧存档字段、原订单实现及其用户数据迁移策略未知；动作还没有账务事务化存盘；没有固定 APK 私有签名记录；没有真实有限做市策略，只允许手工预置有资金/库存的对手账户。切勿卸载原 APK 或覆盖原有持久化键。

## 5. 仅用安卓手机构建APK的操作流程

### 首次准备

1. 在安卓手机浏览器登录/注册 [GitHub](https://github.com/)。
2. **现已有仓库，无需新建**：直接进入 [terminal_x](https://github.com/54854434/terminal_x)，默认分支 `main`。
3. 把工程的 `pubspec.yaml`、`lib/main.dart`、`.github/workflows/build-apk.yml` 上传/创建到相应路径。手机浏览器若隐藏菜单，可开启“桌面版网站”。**文件路径必须保持层级**。
4. 点击仓库的 **Actions**，打开 `Build Android APK`。提交到 `main` 可以自动触发，或在 `workflow_dispatch` 下手动 Run workflow。
5. 如果运行成功，到对应 workflow run 页面 **Artifacts** 下载 `terminal-x-apk`，解压后获取 `app-debug.apk`；先核实此运行确实使用本轮新工作流。
6. 在安卓手机打开 APK，按系统提示允许该来源安装应用，并做首次交易与数据恢复测试。
7. 如果失败，查看 Actions 里**第一处失败步骤**，复制完整关键日志，在新对话提供，用日志定位问题而非重新猜测。

### 稳定升级必须补的环节

- 初期 `--debug` 构建仅用于验证安装；后期需要**固定的私有签名密钥**构建可持续升级的APK。不同云端机器的调试签名可能不一致，无法保证覆盖安装。
- 未做数据导出前**不要随意卸载旧版**，卸载通常会删除App内部数据。
- 添加存档导出/导入，然后迁移到 SQLite+Drift、正式版本签名。
- 不把签名私钥、密钥口令或其他秘密写进仓库源代码；通过 GitHub Actions Secrets 管理。
- GitHub Actions 免费额度、构建平台及第三方Action版本可能变化，以当前后台和错误日志为准。

## 6. 后续开发优先顺序

| 里程碑 | 工作内容 | 阶段状态 |
|---|---|---|
| 0 | 手机上创建仓库，上传工程，GitHub Actions生成并安装调试APK | **已由用户确认完成：首个APK生成并通过8项手机基础测试** |
| 1 | **V0.1b（进行中）**：独立Dart撮合、会话与持久化兼容、Flutter UI接入代码、云测/云编译工作流 | **基于真实源码已生成完整待上传改造包、17项待运行测试；无提交、无新APK、无新实测** |
| 2 | 使用 SQLite + Drift 完整保存账户、委托、成交、持仓、事件 | 未开始 |
| 3 | 专业竖屏UI、交互K线、完整盘口、交易详情 | 未开始 |
| 4 | 持久化订单簿和本地AI做市商、大单真实市场冲击 | 未开始 |
| 5 | 操盘台：算法拆单、资金规模/流动性测量、退出成本 | 未开始 |
| 6 | A股/美股/期货/外汇/加密各自独立市场规则 | 未开始 |
| 7 | 跨市场联动、经济事件、历史回放、压力测试和长时间优化 | 未开始 |

**当前最重要的一步**：阶段A **17/17项Actions测试通过并提交到 `main`**；阶段B需经手机更新UI和带测试门禁的APK构建工作流，等待云端新APK构建与手机实测。保留旧APK与旧应用数据。不要从头初始化仓库，不要跳到五大市场。

## 7. 必须长期坚持的核心技术约束

- 所有成交发生在同一套模拟撮合规则中；**不能用界面点击直接增减资产而不写成交与账务流水**。
- 交易请求与资金/库存校验、执行和账务更新需要原子性，避免重复成交、重复扣款。
- 必须清楚区分订单创建、有效挂单、部分成交、成交完毕、取消、拒绝、过期。
- 买卖盘口、成交记录和实际执行所用流动性需一致；无无限虚拟对手盘。
- 行情/账户可用固定随机种子与事件序列重现，方便测试和分支存档。
- 资金越大越可能出现冲击成本，但并**不能随意强制推高价格**；主要由订单簿深度和AI行为决定。
- 不把模拟股票规则硬编码为所有A股均10%涨跌幅，或所有期货均无限制；市场规则应按品种和日期配置。
- 历史回放模式不能让玩家改变真实已发生的历史价位；若没有历史逐笔/盘口数据，要把衍生盘口明确标注为合成。
- 不接入真实资金/真实交易账户，也不将系统作为真实市场操纵工具。

## 8. 新对话建议直接发这段话

> 请完整阅读我上传的 `TERMINAL_X_HANDOFF.md`，这是我们正在推进的 Terminal X 安卓离线交易/操盘模拟器项目。我只有安卓手机。请不要从头重新策划产品，而是按文档的当前阶段继续落地。我已确认项目交接文件上传GitHub、首个APK生成并在安卓手机上通过8项基础测试。请首先检查当前仓库的工程源码、构建配置与最近成功运行记录，接着按V0.1b计划修复订单簿、资金冻结、部分成交、撤单及账务一致性，添加自动化测试；不要重新创建项目或再要求验证那8项已报告通过的功能。交付的每项修改都要附完整文件、路径、测试及复现办法；最后同步更新这份交接文档。

**仓库已核实**：`https://github.com/54854434/terminal_x`（Public），默认分支 `main`。当前可以直接读取公开源码但连接不具写权限；用户只能安卓手机操作网页+Actions，勿再要求插件或电脑。

## 9. 每次新对话结束要更新的“活跃状态栏”

- **最后更新/交接版本**：2026-10-11 / **1.9**。
- **GitHub仓库**：`https://github.com/54854434/terminal_x`，**Public**，`main`，公开源码可读、当前AI连接无写入权限；用户仅安卓手机操作GitHub网页和云端Actions。
- **最后已核实的 `main` 提交 SHA**：`2faa9db26d38a35a1d5335d606950500a8f9ebad`，由用户网页上传阶段B导入workflow；**并非阶段B源码提交**。阶段A已入库SHA `49836dacb90819e653fadc3bbed47d43c2c2fb83`。
- **阶段A自动化验证**：run `38139622283`、job `114470600752`，成功，日志 `17 tests passed.`，已提交6份文件包括两份Dart引擎/两份测试/依赖与技术文档。
- **阶段B批量构建实测（服务器侧）**：用户已上传 `terminal_x_v01b_stage_B_bulk_v18.zip`（根目录，21,906字节）以及 `.github/workflows/terminal_x_import_stage_b.yml`；run `38140701786`、job `114473807015`，ZIP校验、Flutter设置、17/17测试、`flutter build apk --debug` **全部成功**。随后尝试提交三个文件时GitHub拒绝工作流修改：`refusing to allow a GitHub App to create or update workflow .github/workflows/build-apk.yml without workflows permission`。该run总结果 **failure**，未成功push，Artifact上传步骤 **skipped**；不能声称APK已有可下载产物。
- **GitHub当前代码**：`lib/main.dart`仍是早期原型（blob SHA `5170999c27c1c28098935525ee9e408dc9a8c62e`）；`.github/workflows/build-apk.yml`仍是旧版（blob SHA `ef2ba7e10a0010649f15910abc35198af34447df`）。已通过阶段A的`lib/engine/`、`test/`、`pubspec.yaml`没有被破坏。
- **用户旧APK实测通过**：8/8（启动、100万初始资金、切换双股票、买100/卖50、盘口与成交、限价挂撤、退出恢复）。**阶段B新APK手机安装及实测仍未发生**。
- **APK构建记录/签名**：旧版run `38134148983`、`38139388744`、`38139500807` success（旧UI）；阶段B `38140701786` 编译成功但Artifact未上传。预览包使用调试构建、独立包名`com.terminalx.preview.terminal_x`，具体证书指纹和固定升级签名均待核实；勿卸载旧包，旧存档不可跨应用沙箱直接读取。
- **交接文档状态**：GitHub仓库仍有历史 `docs/TERMINAL_X_HANDOFF_LATEST.md`；规范主路径 `docs/TERMINAL_X_HANDOFF.md` **尚未提交**。本地生成v1.9文件，恢复工作流拟在成功后与`lib/main.dart`一起提交；当前只能把它列为**准备交付，尚未远端验收**。
- **下一件唯一优先事项**：通过手机浏览器把新版`.github/workflows/build-apk.yml`和新`.github/workflows/terminal_x_import_stage_b_recovery.yml`一起上传到`.github/workflows/`，然后手动运行`Terminal X - Recover Stage B and Publish APK`；核对17测试、APK构建、源码/文档推送、Artifact均全绿，记录新的main提交SHA，再下载安装进行回归。
- **未解决问题**：阶段B尚未推送/可下载安装；缺少新版手机实测；新版`shared_preferences`尚非SQLite/Drift事务；真实存档迁移未手机实测、签名持续升级、复杂市场规则、做市策略与性能仍待完成。**完整V0.1尚未完成**。

---

## 10. V0.1b本轮交付文件清单与校验

本轮独立增量包：`terminal_x_v01b_additive.zip`（手动将文件合并至**现有项目**，不是可直接安装的APK或完整Flutter工程）。其中正式交接位置为 `docs/TERMINAL_X_HANDOFF.md`。文件版本标签均为 **V0.1b draft / 2026-10-11**，不得记为用户实测通过。为了验证手机上传内容一致，各文件 SHA-256 如下（以本次生成文件为准）：

- `lib/engine/tx_engine.dart`：`5f62785ac70908633a6a320304d602ffa860d39d7614dfcf3ba4d327b63b7620`
- `test/tx_engine_test.dart`：`8128b3efcdb12dae72095ca73fa4cf6816dd8ed9884eb057fba52265cd073635`
- `.github/workflows/v01b-engine-validation.yml`：`1a42cf84d66c077a7eb42694d83b0e2ba6c5abe8231585b4bb9bb30724d9c12c`
- `docs/V01B_MOBILE_INTEGRATION.md`：`f57c68bef104af64222bde64f09d1a701dbaacc3a917091339d3a284546cc26d`

**MD文件自身不提供静态SHA**（避免把自校验值写入自身引起循环改写）。交接文档中的代码和构建状态以本次可下载包为准；GitHub 提交完成后应记录实际 commit SHA 和 Actions 结果。

## 11. 公开仓库核对与 V0.1b UI/测试门禁集成（交接 v1.5，2026-10-11）

**本节取代先前v1.3/v1.4“私仓无法读取”的历史状态，不删除旧里程碑背景。** GitHub仓库已经公开，读取权限成功。`main` 实际 Flutter `lib/main.dart` 与旧交接猜测相符。`pubspec.yaml` 当前 `version: 0.1.0+1`、`sdk: >=3.5.0 <4.0.0`，运行依赖 `shared_preferences: ^2.5.3`；原仓库缺少测试开发依赖，本轮在`pubspec.yaml`新增`flutter_test` SDK dev_dependency。GitHub `build-apk.yml` 目前没有 `flutter test` 步骤，构建产物`terminal-x-apk`。最新已读HEAD `d9b219d1122f3b83eb08292e5b8f440a88337ecb` 删除了`docs/TERMINAL_X_HANDOFF.md`。历史Actions成功记录、调试签名SHA、用户实际运行时对应HEAD均未独立查到。

**本轮新代码的设计变化（不是已上线功能）：**

1. 在既有`tx_engine.dart`上加入会话`tx_session.dart`，单一钱包/流水账本，2只虚拟股，做市账户现金/可卖股均有限；模拟时间推进重挂报价，但库存/资金不会无条件补充。报价变化为步数驱动的确定性序列。
2. 替换候选`lib/main.dart`：原按钮直改资金的逻辑已迁移至`engine.place()`；盘口展示订单簿中真实未成交量；显示可用/冻结余额、可卖数量、最近逐笔成交和挂撤单。
3. 候选会话快照记录订单、成交、冻结、账本、时间/行情状态、旧订单归档。启动时若新版单键存档缺失，则只读解析旧键 `terminal_state` 的现金/持仓/参考价格/时钟、保留旧字符串成交历史；**旧挂单只归档，避免无预约资金/股票的旧单自动成交**。旧键不覆盖；新版无效存档时停止交易避免回退为默认百万账户。
4. 新增6个会话/旧版迁移单测，连同上一轮11个引擎测试共17个；提供独立云端测试workflow及“APK构建前必须17项测试通过”的新build workflow。
5. 新debug预览包将使用与旧APK不同的安卓applicationId `com.terminalx.preview.terminal_x`，以避免覆写旧APK或陷入不稳定debug签名升级。**因此此预览包无法访问旧APK沙箱存档，迁移只通过测试数据自动化验证，旧版原地迁移尚未实机验证。**

**执行顺序**：A上传引擎、会话、2份测试、测试工作流以及`pubspec.yaml`→Actions绿色；B替换界面和APK流程并恢复交接MD→Actions先test后build→安装独立预览包→用户进行回归。详见本轮`docs/V01B_MOBILE_UPGRADE.md`。实际GitHub同步/Actions/手机验证结果留待下次核实，绝不能提前标绿。


## 12. v1.6 安卓手机批量导入阶段A（2026-10-11）

**本节新增的是上传便利工具，不是已验证的交易功能里程碑。**

用户当前只能安卓手机操作，逐目录手动上传7份阶段A源码容易错放路径。本轮从上轮文件 `terminal_x_v01b_stage_A_engine_tests.zip` 派生**只需两次网页上传操作**的辅助方案：

1. 在公开仓库 `https://github.com/54854434/terminal_x` 的**根目录**通过 `Add file → Upload files` 上传原始 `terminal_x_v01b_stage_A_engine_tests.zip`。文件必须保持原始名称与字节，不要在手机端重新打包。
2. 进入 `.github/workflows/` 目录，上传新生成的 `terminal_x_import_stage_a.yml`，并建议同时上传新单列出的 `v01b-engine-validation.yml`（在文件选择器里一次选两份；如果移动浏览器不能多选，则分别上传）。这两份工作流需用户亲自在浏览器提交，不能指望默认 `GITHUB_TOKEN` 在 workflow 里创建工作流文件。
3. 打开 `Actions → Terminal X - Import Stage A from ZIP → Run workflow`（选择`main`）。工作流先校验输入 ZIP 的 SHA-256、精确路径清单、现有 `pubspec.yaml` 的已知版本以及其他目标文件未被异版改写；**仅**解压根目录 `pubspec.yaml`、`lib/engine/tx_engine.dart`、`lib/engine/tx_session.dart`、`test/tx_engine_test.dart`、`test/tx_session_test.dart`、`docs/V01B_MOBILE_UPGRADE.md`；然后 `flutter pub get` 与 `flutter test test/tx_engine_test.dart test/tx_session_test.dart`。只有测试全绿才通过 `GITHUB_TOKEN` 的 `contents: write` 提交并推送这6份非workflow文件到 `main`。旧 `lib/main.dart`、原 `build-apk.yml` 与旧App存档**不会触碰**。
4. GitHub Actions 使用内建仓库令牌进行的 push 通常**不会自动再触发其他普通 push 工作流**，如单独上传了 `v01b-engine-validation.yml`，请再手动运行 `V0.1b Engine Validation`，检查绿色。测试失败的日志即本轮下一次修复输入；失败时未提交交易源码，保留旧APK。
5. 阶段A成功后，**不得直接声称新版APK已生成**。阶段B的 `lib/main.dart`、`.github/workflows/build-apk.yml` 及完整交接文档仍须按阶段B指导集成、构建与验收。

文件校验：

- `terminal_x_v01b_stage_A_engine_tests.zip`：SHA-256 `122203f2af5dba3cc54cbc8c9b4caaa42ed7e9866885dda977574848202aa7cf`（原阶段A ZIP，包含7份文件）。
- `terminal_x_import_stage_a.yml`：SHA-256 `12760a63583ddc822772d2b49861418b175e97ebfa55b5fc98f9aa1da2b265ce`，建议仓库路径 `.github/workflows/terminal_x_import_stage_a.yml`。
- `v01b-engine-validation.yml`：SHA-256 `846b49782a92916499c38096a40842b2ca2384bfa8832fefaa0a853c87376f7f`，建议仓库路径 `.github/workflows/v01b-engine-validation.yml`。

已知限制：

- 本轮**只在会话内生成了辅助 workflow 和最新版交接文件**；未使用 GitHub 写入，亦未在真实 Actions 运行它。`main` 的最新实时提交需在用户上传前核实；截至上轮成功读取为 `d9b219d1122f3b83eb08292e5b8f440a88337ecb`。
- 新工作流仅支持上述固定阶段A ZIP（SHA 验证写死）；源码后续修改或重新打包必须重新生成并更新校验，不应关闭安全检查。
- GitHub 若因分支保护或仓库安全策略拒绝 `contents: write` 推送，会在 `git push` 出错；不得要求用户将个人访问令牌公开。若需要，可用手机浏览器手动上传对应源码文件作为回退方案。
- 导入 workflow 使用 `workflow_dispatch` 手动触发，避免任意提交或外部PR自动使用写入令牌。ZIP 自身及辅助工作流一旦上传至公开仓库也可被任何人查看；不要添加密码、私有存档、签名私钥。

**状态归类**：用户已实测通过：旧版APK 8/8；代码已写但未编译：V0.1b引擎/UI与本轮导入工作流；构建成功但未实测：无（本轮）；计划中：阶段A云端测试、阶段B安装包验收、SQLite/Drift等。

## 13. 真实 GitHub 阶段A上传、云端测试与提交（交接 v1.7，2026-10-11）

用户在安卓手机通过GitHub网页实际上传下列文件：

- 仓库根目录：`terminal_x_v01b_stage_A_engine_tests.zip`，仓库Blob SHA `c4754a3ec96426a1d0382088e0e5b553267a750e`，16,145字节；与本轮本地下载文件git blob哈希一致，原ZIP的SHA-256见§12。
- `.github/workflows/terminal_x_import_stage_a.yml`：GitHub Blob SHA `fbb422a7c7b19dd7f8c985f13ed823aa7f5c29c1`。
- `.github/workflows/v01b-engine-validation.yml`：GitHub Blob SHA `5886e04db98a08b01e87f98793cce617eaed3aed`。

**测试真实完成**：GitHub Actions 手动导入任务 `https://github.com/54854434/terminal_x/actions/runs/38139622283` 于2026-10-11 12:32:02 UTC启动，最终`success`。Job `114470600752` 的ZIP校验、Flutter安装、依赖解析、17个引擎与会话用例、提交源码全部成功。日志明确含`🎉 17 tests passed.`；`git commit`结果`49836dacb90819e653fadc3bbed47d43c2c2fb83`，已进一步独立读取`main`发现新增引擎/测试及`pubspec.yaml`变更。**这不是仅生成本地ZIP；此次阶段A确实已进入远端仓库。**

**需要区别的失败任务**：阶段A源码提交前，GitHub因YAML上传自动执行独立验证 run `38139500710`，失败原因为`pubspec.yaml`当时缺少`flutter_test`开发依赖；失败记录发生在阶段A成功之前，并非17测试失败。Actions机器人push新commit后普通`push`验证工作流可能不会自动再次触发，可手机手动运行`V0.1b Engine Validation`再复核一次。

**APK历史记录已验证**：旧`Build Android APK` run `38134148983`（#6）全步骤success（包括上传APK Artifact）；此记录只证明旧工作流成功，**并非V0.1b集成APK**。旧APK push运行 #7 (`38139388744`) 与 #8 (`38139500807`) 同样查询到 **completed/success**，但仍是旧UI工作流产物；它们不代表V0.1b阶段B APK已经生成。签名证书指纹未知。

**阶段B下一步**：从已交付的`terminal_x_v01b_stage_B_preview_app.zip`中取出`lib/main.dart`（原仓库目标同路径）与`.github/workflows/build-apk.yml`（原路径），手机GitHub分别替换后运行带先测后构建的APK工作流。阶段BZIP中含旧版本交接文件，**必须改用此次v1.7**并手动上传至`docs/TERMINAL_X_HANDOFF.md`。不要删除/卸载旧APK，保留旧存档；新debug预览包需实测。新代码属于**阶段A单测已绿、阶段B未编译未实测**，不能将17项自动化测试直接表述为安卓功能8项回归完成。


## 14. v1.8 阶段B批量安装包（2026-10-11，待实际运行）

**只准备了发布包和导入工作流，尚未在GitHub上传/运行，不能视为阶段B已完成。** 当前基线为已验证的`main` SHA `49836dacb90819e653fadc3bbed47d43c2c2fb83`，阶段A导入任务 `38139622283` 成功且日志确认17项测试通过。

为减少安卓网页手动替换文件的步骤，本次另生成：

- `terminal_x_v01b_stage_B_bulk_v18.zip`：含新版 `lib/main.dart`、新 `.github/workflows/build-apk.yml` 和最新 `docs/TERMINAL_X_HANDOFF.md`（v1.8）。避免使用老阶段B ZIP附带的v1.5 MD。此ZIP不是可安装APK。
- `terminal_x_import_stage_b.yml`：建议人工上传至 `.github/workflows/terminal_x_import_stage_b.yml`。必须由仓库所有者在网页上发起 `workflow_dispatch`，限定`main`，工作流先核对ZIP的SHA256及路径白名单，再核实基础源码的已知SHA，解压三份文件。
- 运行时使用Flutter安装/依赖解析、17个引擎及会话测试、调试版预览APK云端构建；**只有测试和APK构建成功才尝试把三份文件一次推送至main**，并在成功后上传APK Artifact。新APK与旧原型采取不同Android应用ID，继续保留旧APK和存档。
- 若`GITHUB_TOKEN`缺少修改GitHub Actions工作流文件的权限，自动push可能失败。**失败时不要表示阶段B已入库**：按日志检查后可通过手机网页手动编辑三个目标文件并提交，再运行新`Build Android APK`验证；不得公开PAT，也不要关闭测试门禁。

**手机操作顺序**：先将`terminal_x_v01b_stage_B_bulk_v18.zip`上传仓库根目录；再将`terminal_x_import_stage_b.yml`上传`.github/workflows/`；最后进入Actions手动运行`Terminal X - Import Stage B + APK`，检查解包、测试、APK构建、Commit/Push与上传Artifacts五步全部绿。工作流若未确认commit SHA，不得宣称已同步。GitHub Actions机器人push可能不会自动触发其他workflow，应使用本导入任务的APK Artifact下载安装，并独立执行手机验收。

**可验证的下一步**：真实运行批量导入，拿到成功/失败日志、实际main SHA、APK构建结果；然后用户在安卓手机安装隔离预览包，检查撮合/冻结/撤单/持久化，记录实测并更新交接文档为下一版本。正式签名、SQLite/Drift及旧应用原地升级仍是未完成项。


## 15. v1.9 阶段B真实Actions验证、受限推送与免Token恢复（2026-10-11）

### 实际已发生

1. 用户将 `terminal_x_v01b_stage_B_bulk_v18.zip`（仓库根目录）及 `.github/workflows/terminal_x_import_stage_b.yml`（工作流目录）上传到公开仓库，并手动运行 `Terminal X - Import Stage B + APK`。
2. GitHub Actions run [38140701786](https://github.com/54854434/terminal_x/actions/runs/38140701786)、job `114473807015`。已独立读取实际日志：ZIP SHA校验、已知源码基线检查、Flutter依赖、**17 tests passed.**、`flutter build apk --debug` 均**success**。
3. 提交阶段运行 `git commit` 时形成本地临时提交 `c5478f9`（只有runner本机的临时提交，不是远端GitHub的`main`！）。`git push` 因 `refusing to allow a GitHub App to create or update workflow .github/workflows/build-apk.yml without workflows permission` 被GitHub拒绝。本次run整体 **failure**；APK Artifact上传被跳过。
4. 已复查远端 `main` 仍为 `2faa9db26d38a35a1d5335d606950500a8f9ebad`，未发生阶段B实际代码入库。不要把“APK编译成功”误报为“APK文件已可下载”或“已手机安装”。

### 修复方案（本轮新交付、尚待用户网页操作验证）

- **不使用私人Token，亦不修改仓库为Private/Public之外的安全设置**。由仓库所有者使用安卓手机网页，打开 `https://github.com/54854434/terminal_x/tree/main/.github/workflows`，通过网页同一批上传/替换这两份YAML：
  - `build-apk.yml`：从此前成功编译的阶段B ZIP中提取的经17测试门禁版本，目标路径 `.github/workflows/build-apk.yml`。新版Git blob SHA 预计为`28c5be6c60663b742531bcfbde026d8682cf5c79`。**此文件必须人工提交**；GitHub内置bot没有工作流修改权限。
  - `terminal_x_import_stage_b_recovery.yml`：新增恢复工作流（本轮生成），校验原始ZIP、现有两个引擎与测试、更新后的`build-apk.yml`与`pubspec.yaml` SHA；使用原始ZIP中`lib/main.dart`，并内嵌此完整v1.9交接文档（gzip+base64精确编码，避免额外上传文件）；在内存目录进行测试和构建，通过后**只把`lib/main.dart`和`docs/TERMINAL_X_HANDOFF.md`推送到main**，不会由bot碰`.github/workflows`；接着上传APK Artifact。
- 完成网页上传后，打开 GitHub `Actions → Terminal X - Recover Stage B and Publish APK → Run workflow (main)`。**预期**测试和构建通过，机器人push两份普通文件、`Upload APK`全绿；运行状态以GitHub真实结果为准。本工作流有安全基线保护和hash校验，不会任意覆盖已有变化，也不主动清理旧存档。
- 预览APK为新的Android应用ID，与旧App独立共存。确认Actions有 `terminal-x-v01b-stage-b-preview-debug` Artifact 后才安装，不能使用失败run中未上传的APK。安装后用户实测交易、冻结可用资金与股票、限价部分成交和撤单、重启恢复、两资产切换，检查旧App仍可使用。**未实测前不得写成手机验收通过。**
- 如果恢复工作流失败，读取真实失败步骤及日志，不要反复盲目上传，也不要申请用户公开密码、令牌或签名密钥。

### 连续性和技术约束

保留 §0.1 长期交接规则、只安卓手机开发、离线单机金融仿真、最终SQLite/Drift持久化、固定签名、价格时间优先和账务一致性、有限做市商、V0.1两只股票初期范围；后续继续以`docs/TERMINAL_X_HANDOFF.md`为唯一最新版标准路径，旧的`docs/TERMINAL_X_HANDOFF_LATEST.md`仅保留历史参考。本节记录的恢复工作流还未在远端执行，其成功状态、未来提交SHA与手机实测需在下次复查后更新v2.0。
