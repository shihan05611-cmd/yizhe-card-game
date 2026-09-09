# 真实卡牌 Run 模拟与主命中快照修复（2026-09-08）

## 已完成

`res://tests/simulate_real_runs.gd` 使用 M5 权威 Run 生命周期和 `RoguelikeBattleAdapter` 启动每场战斗。战斗中只调用真实 `BattleController.play_card(instance_id)` 和 `end_player_turn()`；不注入胜利、不写入 HP / 伤害 / 货币，不改生产数值或策略。每场限制 60 回合，每颗种子限制 30 个地图节点。

模拟暴露并已修复 `primary_hit death flag must match defender state`：`DamagePipeline.apply()` 在返回 B0 主伤害结果前，会同步分发 `damage_applied`、`unit_damaged` 与 `hp_threshold_crossed`。hook 可在此期间追击并杀死同一目标，因此返回后 `target.alive` 已不代表主伤害的历史结果。

修复位于：

- `systems/combat/piece_attack.gd`：从不可变 B0 `hit.died` 生成 `defender_alive_after_primary_hit` 历史字段。
- `systems/combat/piece_reactions.gd`：校验 `primary_hit.died` 与该历史字段，而不是与 hook 后的当前防守方状态相等；当前状态仍用于反应守卫。
- `tests/piece_attack_test.gd`：新增由 `basicAttackHit` hook 通过统一 `DamagePipeline.apply()` 杀死目标的最小回归，断言反应继续完成、事件顺序保持不变。
- `tests/piece_reactions_test.gd`、`tests/energy_rule_test.gd`：更新封闭请求形状以提供历史字段。

这不把追击/反伤/其他 hook 的后续击杀改写为 `primary_hit.died`；攻击总结果的 `primary_died` 仍表示主目标在整段攻击结束时是否死亡，供后续目标选择使用。

## 已执行验证

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\primary-hit-snapshot-focused.log' --script res://tests/run_m3b.gd
```

结果：`tests=72 assertions=943 failures=0`。包含 Piece Attack、Piece Reactions、Energy Rule、Battle Card Session 等直接回归；Windows 根证书读取错误未影响测试。

修复后的基线三种子实际运行曾输出以下汇总。**不要把 `.godot/test-logs/real-run-simulation.log` 作为该次证据**：该文件仍是修复前的 10 场 / 155 回合 snapshot 错误日志；下面的修复后基线结果只保留在当次 PTY stdout 记录中。

| 种子 | 起始英雄 | 到达位置 | 结果 | 战斗（胜/负） | 已结束回合 |
| --- | --- | --- | --- | ---: | ---: |
| `real-run-001` | 骑士（4） | 第 2 章，第 11 节点 | `failed` | 5（4/1） | 55 |
| `real-run-002` | 元帅（3） | 第 1 章，第 10 节点 | 仍为 `fighting`，单场达到 60 回合上限 | 4（3/0） | 102 |
| `real-run-003` | 影狩（9） | 第 1 章，第 10 节点 | `failed` | 4（3/1） | 91 |

汇总：13 场真实战斗、248 个已结束玩家回合、平均 19.08 回合/场；0 次完整通关、2 次正常失败、1 次有界回合上限。修复前的两项 `primary_hit` 解析异常已不再出现。

第 2 颗种子的上限记录没有输出节点类型或双方 HP 快照，因此不能据此断言它是 Boss 或真正僵局；它只证明当前 60 回合限制截断了该场。下一次恢复时应在模拟器的回合上限分支记录当前节点 `type`、双方总 HP / 最大 HP、round、手牌与 SP，再区分 Boss 持久战、策略停滞或上限过紧。

## 保守成长单一样本：玩法链路证据，非平衡验收

保守成长策略是测试参数，不改变生产策略或数值：开局优先宁不凡（6）/元帅（3）/炎术士（5），招募优先这三位成长英雄；受伤时优先锻坊，其余优先普通战斗和事件、回避非必要精英；商店只购买遗物以避免自由技过度稀释。

先通过无战斗的生命周期候选检查，确认只有 `real-run-002` 提供宁不凡：`元帅(3), 影狩(9), 宁不凡(6), 炎术士(5)`。随后仅运行该单一样本，并在每条真实命令后确认表现事件，避免未消费的表现事件队列拖慢视图复制。日志在 `.godot/test-logs/real-run-002-growth.log`。

该样本以宁不凡起始，依次在第 1 章列 0、1、2、5、8 的五场战斗获胜（回合数 4、4、3、7、7），随后第 1 章列 9 Boss 到达 60 回合限制：

- Boss：敌方总 HP `1102/4446`；核心槽为 `723/3946`，其余存活槽为 `42/100`、`37/100`、`100/100`、`100/100`、`100/100`。
- 我方总 HP `1679/2250`；SP `1/11`；round `61`；手牌为拳劲、封命、灼痕标记和小回血。
- 单局累计：6 场、5 胜、0 负、85 个已结束玩家回合；状态因有界 60 回合限制保留为 `fighting`。

模拟器现有两个明确边界：每场 60 回合，以及每回合 128 张卡命令 / 每场 4096 条命令。达到任一边界会记录节点、HP、round、SP、牌堆和手牌，再取消开放的 Run battle launch，不伪造结算。

用户已决定模拟到此停止：不再运行 150 回合、额外种子、优化策略或平衡搜索。这些样本证明真实 Run、招募、奖励、商店/锻坊、卡牌命令和 Boss 入口可推进；它们不构成通关率、数值平衡或难度验收。
