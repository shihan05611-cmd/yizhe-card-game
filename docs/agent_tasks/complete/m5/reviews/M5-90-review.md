# M5 独立最终 Re-Review

- 评审角色：Review Agent
- 复验日期：2026-09-08
- 目标里程碑：M5（M5-01 至 M5-06）
- 复验对象：首次 Review 阻断项修复及完整 M5 回归
- 评审性质：只读最终验收；未修改实现、测试、任务状态或 handoff

## 范围

本轮重新检查：

- Run 封闭契约、事务 RNG、地图和遭遇；
- 奖励、商店、锻造、事件的权威快照、原子结算、伪造/过期/重复提交回滚；
- 免费技能多重集、普通及职业升级遗物的经济与战斗接线；
- Run 阵容六槽顺序、职业基础属性、遗物/永久成长/HP 比例的投影顺序；
- 胜利/失败、跨战 HP、永久成长提交及 M4 direct 配置兼容；
- 三种神通与两件进化遗物在 Run、GameRoot、BattleController、UI、InputMap、E2E 的休眠边界；
- 固定种子三章无头 E2E。

未运行 1000 次稳定性，不扩展至 M6、平衡或正式 Run UI。除本报告外未写入任何文件。

## 本轮冻结基准

复验期间收到用户明确的新产品规则：M5 Run 六槽固定为槽 1–3 `shield`、槽 4 `assassin`、槽 5 `crossbow`、槽 6 `banner`，目的是尽早展示兵种丰富度。该规则有意覆盖旧 Web/M1 的 `[shield ×3, crossbow ×3]` 默认阵容，优先级高于旧 parity 基准，不作为缺陷。

偏离范围保持受控：新阵容仅用于 M5 Run 建队；M1 目录中的 Web 默认映射未被篡改，M4 direct 配置仍保持六槽 `default`。`docs/m5-handoff.md` 已记录新的 Run 冻结阵容和投影顺序。

## 验证命令与结果

### Godot 4.7.1 editor parse/import

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --editor --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\m5-90-rerun-editor-20260908.log' --quit
```

- 退出码：0；项目扫描、全局类名和 autoload 初始化完成，无项目脚本 Parse Error。
- 系统根证书读取失败和全局 `editor_settings-4.7.tres` 无法保存为受限 Windows 环境告警，不是项目解析失败。

### 累计 M5 focused

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\m5-90-rerun-focused-20260908.log' --script res://tests/run_m5_06.gd
```

- 退出码：0。
- `tests=46 assertions=2730 failures=0`。
- 新增断言覆盖新冻结六槽顺序、职业基础属性、`crossbowPlus` 修正、`shieldPlus` 经真实 DamagePipeline 触发，以及 M4 direct 六槽仍为 `default`。

### regular（排除 stability）

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\m5-90-rerun-regular-20260908.log' --script res://tests/run_regular_without_stability.gd
```

- 退出码：0。
- `tests=369 assertions=13685 failures=0`。
- `ARCHITECTURE REAL violations=0`、`SAFE_FIXTURE violations=0`；fixture violations/scan failures 是扫描器预期负向夹具。
- runner 明确输出 `OMITTED BY USER REQUEST: res://tests/m2_battle_stability_test.gd`。

### diff 与静态核对

```powershell
git diff --check
rg -n "RUN_ALLY|build_default_ally_mapping|shieldPlus|crossbowPlus|class_id|direct|default" app/battle_bootstrap.gd tests/m5_battle_bridge_test.gd data/catalogs/piece_class_catalog.gd
rg -n "dormant_shentong|DormantShentong|use_shentong|selected_shentong|shentong_charge|shentong_assault|shentong_sacrifice|evolvedRelic|evolved_relic" app autoload systems ui project.godot --glob '!systems/roguelike/dormant_shentong_*.gd' --glob '!systems/relics/relic_system.gd'
```

- `git diff --check`：退出码 0，无 whitespace error。
- 神通生产接线搜索无命中；奖励、商店、锻造和 Run 战斗仍显式排除两件进化遗物。
- Run 新冻结阵容、M4 direct 阵容以及职业遗物断言均有生产代码与测试对应。

## 复验结论依据

- Run 战斗不再把六枚友方棋子全部创建为 `default`；`BattleBootstrap._run_allies()` 按用户冻结顺序投影四类职业。
- 职业 HP、ATK、block/crit 先进入战斗状态，再叠加永久成长、职业遗物和槽位 HP 比例，顺序符合交接契约。
- `crossbowPlus` 的 -20 最大生命和 +10% 追击概率在槽 5 机弩上可观察，且不会命中旗兵；`shieldPlus` 通过真实 DamagePipeline 的格挡事件触发恢复。
- M4 direct 配置继续生成六槽 `default`，常规 M2–M4 回归保持全绿。
- Run/RNG、地图、经济权威回滚、重复免费技能、普通遗物动作、胜负/HP/永久成长提交和三章 E2E 均通过累计回归。
- 三种神通和两件进化遗物有独立迁移测试，同时未进入 Run、GameRoot、BattleController、UI、InputMap 或 E2E。

## 发现项

没有剩余阻断项。

已记录一项经用户批准的 Web 偏离：M5 Run 使用 `[shield, shield, shield, assassin, crossbow, banner]`，而旧 Web/M1 默认映射仍为 `[shield, shield, shield, crossbow, crossbow, crossbow]`。该差异是本轮明确的新冻结产品规则，且实现范围未外溢至 M1 数据定义或 M4 direct 入口。

## 最终结论

**PASS**
