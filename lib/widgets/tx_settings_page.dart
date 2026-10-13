import 'package:flutter/material.dart';

import 'tx_terminal_theme.dart';

/// The player-facing settings centre.
///
/// This widget deliberately owns presentation only. Runtime, market and
/// SQLite policies stay in the existing home state and are passed in through
/// callbacks, so the settings screen cannot create a second game clock or a
/// second persistence path.
class TxSettingsPage extends StatelessWidget {
  const TxSettingsPage({
    super.key,
    required this.appVersion,
    required this.rustStatus,
    required this.ready,
    required this.running,
    required this.speed,
    required this.actualMultiplier,
    required this.pulseSeconds,
    required this.automaticSaveMinutes,
    required this.automaticSaveDraft,
    required this.checkpointInterval,
    required this.checkpointDraft,
    required this.currentRevision,
    required this.pendingSave,
    required this.pendingOperations,
    required this.pendingGameMinutes,
    required this.storageSummary,
    this.onToggle,
    this.onManualTick,
    this.onCustomSpeed,
    this.onSpeedPreset,
    this.onSpeedDelta,
    this.onPulsePreset,
    this.onCustomPulse,
    this.onAutomaticSaveDraftChanged,
    this.onSaveAutomaticSave,
    this.onCheckpointDraftChanged,
    this.onSaveCheckpoint,
    this.onInspectStorage,
  });

  final String appVersion;
  final String rustStatus;
  final bool ready;
  final bool running;
  final int speed;
  final String actualMultiplier;
  final int pulseSeconds;
  final int automaticSaveMinutes;
  final int automaticSaveDraft;
  final int checkpointInterval;
  final int checkpointDraft;
  final int currentRevision;
  final bool pendingSave;
  final int pendingOperations;
  final int pendingGameMinutes;
  final String? storageSummary;

  final VoidCallback? onToggle;
  final VoidCallback? onManualTick;
  final VoidCallback? onCustomSpeed;
  final ValueChanged<int>? onSpeedPreset;
  final ValueChanged<int>? onSpeedDelta;
  final ValueChanged<int>? onPulsePreset;
  final VoidCallback? onCustomPulse;
  final ValueChanged<int>? onAutomaticSaveDraftChanged;
  final VoidCallback? onSaveAutomaticSave;
  final ValueChanged<int>? onCheckpointDraftChanged;
  final VoidCallback? onSaveCheckpoint;
  final VoidCallback? onInspectStorage;

  static const _speedPresets = <int>[
    1, 5, 10, 30, 60, 100, 300, 600, 1200, 3600,
  ];
  static const _pulsePresets = <int>[5, 10, 15, 30, 60];
  static const _savePresets = <int>[1, 5, 15, 30, 60];
  static const _checkpointPresets = <int>[8, 16, 32, 64];

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
    children: [
      _heroCard(),
      _sectionTitle('运行控制', '把游戏节奏、实时盘口和已落盘状态放在同一处'),
      _runtimeCard(),
      _sectionTitle('实时盘口', '盘口更新频率独立于 SQLite 自动保存周期'),
      _marketCard(),
      _sectionTitle('存档策略', '设置只改变写入策略，不改变已经保存的数据'),
      _storageCard(),
      _sectionTitle('诊断与版本', '只读信息用于确认 Rust、SQLite 和当前构建状态'),
      _diagnosticsCard(),
      _roadmapCard(),
    ],
  );

  Widget _heroCard() => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF172A43), TxTerminalColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: TxTerminalColors.primary.withAlpha(41),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.tune, color: TxTerminalColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('设置中心', style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                )),
                const SizedBox(height: 4),
                const Text('游玩、盘口、存档与诊断', style: TextStyle(
                  color: TxTerminalColors.secondaryText,
                )),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _statusChip(
                    ready ? '运行入口已就绪' : '等待存档校验',
                    ready ? TxTerminalColors.buy : Colors.amberAccent,
                    ready ? Icons.check_circle_outline : Icons.hourglass_top,
                  ),
                  _plainChip('v$appVersion', Icons.verified_outlined),
                ]),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: .2,
        )),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(
          fontSize: 12, color: TxTerminalColors.secondaryText,
        )),
      ],
    ),
  );

  Widget _runtimeCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _metric('当前倍率', '$speed×')),
              Expanded(child: _metric('实测提交速度', actualMultiplier)),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: onToggle,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              label: Text(running ? '暂停行情' : '开始行情'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: onManualTick,
              icon: const Icon(Icons.skip_next),
              label: const Text('推进 1 分钟'),
            )),
          ]),
          const SizedBox(height: 14),
          _labelRow('倍率预设', '已选 $speed×'),
          const SizedBox(height: 7),
          _horizontalChoices(
            _speedPresets,
            selected: speed,
            label: (value) => '$value×',
            onSelected: onSpeedPreset,
          ),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(
              tooltip: '降低倍率',
              onPressed: onSpeedDelta == null ? null : () => onSpeedDelta!(-1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(child: Text(
              '适合长时间运行；实际速度只统计已经提交的游戏分钟',
              style: TextStyle(
                fontSize: 11, color: TxTerminalColors.secondaryText,
              ),
            )),
            IconButton(
              tooltip: '提高倍率',
              onPressed: onSpeedDelta == null ? null : () => onSpeedDelta!(1),
              icon: const Icon(Icons.add_circle_outline),
            ),
            TextButton(onPressed: onCustomSpeed, child: const Text('自定义')),
          ]),
        ],
      ),
    ),
  );

  Widget _marketCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelRow('盘口刷新节奏', '当前每 $pulseSeconds 游戏秒'),
          const SizedBox(height: 8),
          _horizontalChoices(
            _pulsePresets,
            selected: pulseSeconds,
            label: (value) => '$value 秒',
            onSelected: onPulsePreset,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onCustomPulse,
              icon: const Icon(Icons.tune, size: 17),
              label: const Text('自定义 5～60 秒'),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '盘口由 Rust 实时核心计算；此处只调整真实盘口同步节奏，'
            '不会伪造成交，也不会替代 SQLite 原子保存。',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    ),
  );

  Widget _storageCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelRow('自动保存周期', '当前每 $automaticSaveMinutes 个游戏分钟'),
          const SizedBox(height: 8),
          _horizontalChoices(
            _savePresets,
            selected: automaticSaveDraft,
            label: (value) => '$value 分钟',
            onSelected: onAutomaticSaveDraftChanged,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onSaveAutomaticSave,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存自动保存周期'),
          ),
          if (pendingSave) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: automaticSaveMinutes <= 0
                  ? null
                  : (pendingGameMinutes / automaticSaveMinutes)
                      .clamp(0.0, 1.0)
                      .toDouble(),
              minHeight: 5,
            ),
            const SizedBox(height: 5),
            Text(
              '当前有 $pendingOperations 项待保存 · $pendingGameMinutes / '
              '$automaticSaveMinutes 个游戏分钟',
              style: const TextStyle(
                color: TxTerminalColors.primary, fontSize: 12,
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('当前没有待保存模拟分钟', style: TextStyle(
                fontSize: 12, color: TxTerminalColors.buy,
              )),
            ),
          const Divider(height: 26),
          _labelRow('完整检查点', '当前每 $checkpointInterval 次成功保存'),
          const SizedBox(height: 8),
          _horizontalChoices(
            _checkpointPresets,
            selected: checkpointDraft,
            label: (value) => '$value 次',
            onSelected: onCheckpointDraftChanged,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onSaveCheckpoint,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('保存检查点周期'),
          ),
          const SizedBox(height: 7),
          const Text(
            '自动保存周期控制连续行情写入频率；完整检查点只负责加快恢复。'
            '玩家下单、切后台和退出前仍会强制保存。',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    ),
  );

  Widget _diagnosticsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _diagnosticRow(Icons.memory_outlined, 'Rust 实时核心', rustStatus),
          const SizedBox(height: 10),
          _diagnosticRow(
            Icons.save_outlined,
            'SQLite 状态',
            '当前修订 r$currentRevision${pendingSave ? ' · 内存有待保存状态' : ' · 已落盘'}',
          ),
          const SizedBox(height: 10),
          _diagnosticRow(
            Icons.data_usage_outlined,
            '数据库占用',
            storageSummary ?? '尚未读取；读取是只读诊断，不删除历史快照',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onInspectStorage,
            icon: const Icon(Icons.storage_outlined),
            label: const Text('读取 SQLite 占用诊断'),
          ),
        ],
      ),
    ),
  );

  Widget _roadmapCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.auto_awesome_outlined, color: TxTerminalColors.cyan),
            SizedBox(width: 8),
            Text('内容扩展预留', style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15,
            )),
          ]),
          const SizedBox(height: 8),
          const Text(
            '下一阶段将在真实交易核心之上增加市场事件、任务/成就、'
            '更多模拟标的和可切换信息密度；当前这里只展示规划，尚未伪装成已实现功能。',
            style: TextStyle(fontSize: 12, color: TxTerminalColors.secondaryText),
          ),
          const SizedBox(height: 11),
          Wrap(spacing: 7, runSpacing: 7, children: [
            _plainChip('市场事件', Icons.bolt_outlined),
            _plainChip('任务与成就', Icons.flag_outlined),
            _plainChip('多市场看板', Icons.dashboard_outlined),
            _plainChip('UI 动效', Icons.animation_outlined),
          ]),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: TxTerminalColors.raised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TxTerminalColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          color: TxTerminalColors.secondaryText, fontSize: 11,
        )),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800,
        )),
      ],
    ),
  );

  Widget _labelRow(String label, String detail) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(child: Text(label, style: const TextStyle(
        fontWeight: FontWeight.w700,
      ))),
      Flexible(child: Text(detail, textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 11, color: TxTerminalColors.secondaryText,
        ))),
    ],
  );

  Widget _horizontalChoices(
    List<int> values, {
    required int selected,
    required String Function(int) label,
    required ValueChanged<int>? onSelected,
  }) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final value in values)
        Padding(
          padding: const EdgeInsets.only(right: 7),
          child: ChoiceChip(
            label: Text(label(value)),
            selected: selected == value,
            onSelected: onSelected == null ? null : (_) => onSelected(value),
          ),
        ),
    ]),
  );

  Widget _diagnosticRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: TxTerminalColors.primary),
      const SizedBox(width: 9),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(
            fontSize: 12, color: TxTerminalColors.secondaryText,
          )),
        ],
      )),
    ],
  );

  Widget _statusChip(String label, Color color, IconData icon) => Chip(
    avatar: Icon(icon, size: 16, color: color),
    label: Text(label, style: TextStyle(color: color, fontSize: 11)),
    side: BorderSide(color: color.withAlpha(89)),
    backgroundColor: color.withAlpha(23),
    visualDensity: VisualDensity.compact,
  );

  Widget _plainChip(String label, IconData icon) => Chip(
    avatar: Icon(icon, size: 15, color: TxTerminalColors.secondaryText),
    label: Text(label, style: const TextStyle(
      color: TxTerminalColors.secondaryText, fontSize: 11,
    )),
    side: const BorderSide(color: TxTerminalColors.border),
    backgroundColor: TxTerminalColors.raised,
    visualDensity: VisualDensity.compact,
  );
}
