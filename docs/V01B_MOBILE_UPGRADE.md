# Terminal X V0.1b：安卓手机 GitHub 集成与验收

本包针对 2026-10-11 `54854434/terminal_x` 的真实 `main` 分支设计（读取时 SHA `d9b219d1122f3b83eb08292e5b8f440a88337ecb`）。如 GitHub 内容已变化，先重新检查差异，不要直接覆盖。

## 交付范围（不是已完成验收）

* `pubspec.yaml` — 在原工程依赖基础上增加 `flutter_test` 开发依赖。
* `lib/engine/tx_engine.dart` — 有状态撮合、现金/持仓冻结、FIFO、多价位部分成交、逐笔成交/流水和JSON快照。
* `lib/engine/tx_session.dart` — 两个品种、现金库存受限的本地合成流动性提供者、可复现手动时钟、新版存档结构和旧演示存档的安全资产迁移。
* `test/tx_engine_test.dart`、`test/tx_session_test.dart` — 共17个测试用例；仅已编写，**尚未在本环境执行**。
* `.github/workflows/v01b-engine-validation.yml` — 独立云端单元测试。
* `lib/main.dart` — 替换交易按钮直改余额的原型逻辑，显示真实订单簿/冻结/成交/委托状态。
* `.github/workflows/build-apk.yml` — **先运行两个测试文件，再构建 APK**；通过 `--org com.terminalx.preview` 为本次试用包设置不同于旧包的 Android 应用ID。
* `docs/TERMINAL_X_HANDOFF.md` — 版本1.5，最新交接主文件。

**需更新 `pubspec.yaml` 的 `dev_dependencies`，添加 `flutter_test`；正式运行依赖 `shared_preferences` 保持不变。**

## 手机操作，分两阶段进行

在安卓手机浏览器中打开 https://github.com/54854434/terminal_x，必要时开启浏览器「桌面版网站」。先下载本 ZIP 并解压，然后在 GitHub 对应目录点击 `Add file` → `Upload files` 上传文件；若已存在同名文件可走 `Edit` 替换内容。每个文件必须保留对应目录层级；不要把 `lib/engine/` 文件上传到仓库根目录。不要上传整个 ZIP 当作源码。

### 阶段 A：不触碰旧App，先验证交易引擎

1. 用包内的 `pubspec.yaml` 更新仓库根目录 `pubspec.yaml`（添加 `flutter_test` 开发依赖，其他原依赖保留）。
2. 上传 `lib/engine/tx_engine.dart` 和 `lib/engine/tx_session.dart` 到仓库的 `lib/engine/`。
3. 上传 `test/tx_engine_test.dart` 和 `test/tx_session_test.dart` 到 `test/`。
4. 上传 `.github/workflows/v01b-engine-validation.yml` 到 `.github/workflows/`。
5. 进入 **Actions → V0.1b Engine Validation → Run workflow**，确认在 `main` 运行成功（绿色勾）。若失败，复制**第一条错误消息**及对应文件行号，本轮不进入阶段B。

旧 `.github/workflows/build-apk.yml` 在阶段A期间仍可能因提交自动构建**旧版原型**；不要把该构建当成 V0.1b 验收结果。

### 阶段 B：只在阶段A测试通过后

1. 上传新版 `lib/main.dart` 覆盖旧 `lib/main.dart`。
2. 上传新版 `.github/workflows/build-apk.yml` 覆盖旧工作流。新工作流先执行 `flutter test test/tx_engine_test.dart test/tx_session_test.dart`，失败时不运行 `flutter build apk`。
3. 上传 `docs/TERMINAL_X_HANDOFF.md`。目前 GitHub 已删除该路径，本次是**恢复文件**。
4. 进入 **Actions → Build Android APK**，在最新 `main` 提交上点击 **Run workflow**。确保 `Test engine and recovery before building APK` 和 `Build APK` 都成功。下载 `terminal-x-apk` Artifacts，解压得到 `app-debug.apk`。
5. 安装到安卓手机：新 APK 使用 `com.terminalx.preview.terminal_x` **独立试用应用ID**，与旧APK并存、不读取旧APK沙箱数据。请保留旧APK，千万不要为了安装试用包而卸载旧版。

## 手机实测建议

1. 试用版打开，初始现金100万元；双股票能切换。
2. SIM-A01 市价买100股：成交、现金减少、持仓增加，盘口对应卖量减少。
3. SIM-A01 市价卖50股：成交、持仓减少、现金增加。
4. SIM-A02 市价买300股：限深五档合计初始仅245股，剩余55股取消，不能无限成交。
5. 切换为限价单：以低于当前卖一价的价格挂买单（例如8.00元买50股）：显示现金冻结，重复买单因可用余额约束；撤单释放冻结。
6. 限价卖出持有股票：减少可卖数，不能重复超卖；撤单释放。
7. 退出/重进试用App：资产、挂单及冻结数据恢复；继续推进时间不发生重复成交。
8. 点击“推进行情一步”：同条件下价差报价可复现，挂单可由新流动性触发。
9. 检查委托状态/逐笔成交价；成交价应是对手盘限价，多档大单可观察滑点。

## 历史存档与构建签名警告

* 原型原存档在旧应用沙箱键 `terminal_state`；V0.1b 使用键 `terminal_x_v01b_state`，即使未来保留同包名升级也不覆盖原键。
* 若在**相同应用ID、相同签名**的未来发行包内首次使用 V0.1b，支持迁移旧账户现金、持仓、参考价格及步骤；由于旧挂单没有冻结账务，旧挂单**仅作为非活动档案保留**，不自动提交。旧字符串成交记录仅展示，不作为新引擎账务流水。
* 此次 Actions 构建使用不同应用ID，所以**无法直接读取原APK内部旧存档**；这是刻意的安全隔离，不应将“保存恢复通过”误说成“旧APK原地升级迁移通过”。
* 生产级原地升级前必须固定私有APK签名证书、规划安全导出/导入旧存档、迁移SQLite/Drift。Github Actions新机器的debug签名可能不同，切勿贸然卸载旧版。
* shared_preferences 仍不是SQLite事务数据库；所有账务目前在单个引擎状态中计算，并序列化到新版单键快照。大量订单长时间模拟还需性能优化。

## 问题排查

* Actions中如 `flutter test` 失败：粘贴测试名称、第一条出错栈、行号；不要跳过测试直接构建。
* APK无法安装：检查是否已存在相同应用ID但不同签名的旧试用包；**不要卸载原有生产原型以解决试用版安装问题**。
* 构建成功但进入App提示存档损坏：保持存档及应用安装状态，先提交报错文本；新版App会停止交易，不会自动清除存档。
