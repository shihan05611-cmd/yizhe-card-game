# M3 卡牌玩法与战斗会话交接

## 状态

**M3 已实现并通过当前自动测试；独立 `M3A_GATE` 与 `M3_FINAL` Review 均为 PASS，模块中枢已完成规则证据整合，等待项目总集成验收。** 本文冻结代码接口和已有证据，不表示玩法数值已经完成产品验收。

## 已实现范围

- 从 M1 自由技、弈者与英雄能力目录派生唯一卡牌目录；静态 `CardDefinition` 与运行时 `CardInstance` 分离。
- draw/hand/discard/exhaust 四区、实例守恒、手牌上限 7、确定性洗牌、回合新增抽牌、成功去向、消耗、回手、费用影子层和串行出牌队列。
- 唯一玩家出牌事务：权威校验、实付 SP、M2 handler 单次执行、成功去向/次数、稳定事件、充能与大招生成。
- 由显式 roster 与自由技 ID 多重列表组装战斗牌库；同名自由技逐份生成独立实例，主动专属技各一张，骑士被动不生成卡但计入 N。
- 完整无头玩家回合：组装/洗牌与首抽 → 连续出牌 → 显式结束 → 先弃手 → M2 `RoundResolver` → 保留结算中新生成的大招 → 非终局新增抽 `2+N`。
- 终局不再抽牌或重复 finalize；已提交失败会停止会话/队列，不自动重试。
- 敌方继续使用 M2 旧式技能选择、SP、能量和前后大招顺序，不进入玩家卡牌桥。

明确排除：M4 场景、手牌 UI、拖拽/动画/倍速；M5 奖励、商店、招募交易、Run 状态与存档；M6 批量模拟和数值调整。M3 只消费调用方注入的 roster 与自由技 ID 多重列表。

## 权威与接口边界

| 权威/入口 | 冻结职责 |
| --- | --- |
| `CardCatalog` | 从 M1 技能/能力目录派生卡牌静态定义；不复制伤害、治疗、Buff 数值或 handler。 |
| `BattleDeckAssembler.assemble(config)` | 接受 `card_catalog`、M1 player/exclusive 目录、`deployed_hero_ids` 与 `free_skill_ids`；整次校验后返回有序卡 ID、定义与 N。输入含 `basicDamage` 时整次拒绝。 |
| `HandRuntime` | 唯一牌区与实例状态权威；独立 `deck` RNG、四区迁移、费用层、成功次数和队列状态都在此。 |
| `HandManager` | Node/Autoload 薄适配。`start_battle_session`、`play_card`、`end_player_turn` 转发纯会话；会话存在时拒绝外部直接 draw/move/create/raw command，避免第二个回合所有者。 |
| `CardCombatBridge` | 唯一玩家卡牌效果事务；通过既有 M2 `EffectRegistry` 精确执行一次，不自行计算伤害。 |
| `PlayerEnergyCoordinator` | 所有玩家能量变化的满阈值检查与大招卡生成；敌方能量不经过此入口。 |
| `BattleCardSession` | 持有一个 `BattleRuntime` 与一个 `HandRuntime` 的会话边界；负责牌库初始化、首抽、连续出牌、显式结束和跨回合顺序。 |
| `BattleRuntime` / `RoundResolver` | 继续拥有 canonical BattleState 与 M2 回合顺序。`RoundResolver.m3_obligations` 仅保留兼容字段，内容已改为三条真实 `BattleCardSession` 职责；由会话结果标记 `fulfilled` 或终局 `skipped_terminal`。 |

`BattleCardSession` 的启动配置为：

```gdscript
{
    "battle_runtime": battle_runtime,
    "battle_seed": battle_seed,
    "deployed_hero_ids": [1, 4, 9],
    "free_skill_ids": ["smallHeal", "smallHeal", "pieceBlock"],
}
```

`deployed_hero_ids` 必须与 live `BattleState.player_heroes[].deployed` 完全一致。会话自己从 `BattleRuntime.catalogs` 重建卡牌目录并派生 deck RNG，调用方不能注入另一份卡牌真相。M4 应通过 `HandManager.play_card(CardPlayRequest)` 和 `HandManager.end_player_turn()` 操作，不能绕过会话直接修改牌区或调用 `BattleRuntime.resolve_round()`。

固定回合顺序为：

```text
end_player_turn
  -> HandRuntime.end_player_turn（弃当前手牌、清 until-turn 费用）
  -> BattleRuntime.resolve_round
       -> enemy heroes
       -> ally/enemy pieces slot 1..6
       -> enemy/ally burn
       -> finalize
  -> 若非终局，HandRuntime.draw_for_turn(N)
```

抽牌返回中的 `HAND_FULL`/`DECK_EMPTY` 表示固定次数中的失败尝试，不会撤销已经完成的合法抽牌，也不会使完整会话误判为未提交。生成大招本身不消耗正常抽牌尝试。

## Q1–Q8 最终口径

| 决议 | 首版冻结口径 |
| --- | --- |
| Q1 | 返回手牌优先于默认消耗去向；消耗只决定成功打出后的去向。 |
| Q2 | “本局只能成功打出一次”只在成功结算后记账；validator/preflight 或结算失败不消耗次数。 |
| Q3 | 满手生成的大招插入抽牌堆顶。 |
| Q4 | 能量满的瞬间先清零并生成大招卡；单次能量事件最多生成一张。 |
| Q5 | 影狩【潜影】成功后回手，同回合无 SP/validator 之外的次数额度。 |
| Q6 | 起始牌库由当前上阵主动专属技各一张与调用方注入的初始自由技各一张组成；具体初始数量留待 M6 调整。 |
| Q7 | 卡牌静态数据使用 GDScript `Resource`/目录承载。 |
| Q8 | 首版暂时移除 `basicDamage` 卡；它不进入卡牌目录、装配或玩家桥。底层 M1/M2 定义与 handler 保留，以兼容敌方旧规则；这不是暴击率决议。 |

## R-001–R-019 证据映射

| ID | 当前证据 | 后续边界 |
| --- | --- | --- |
| R-001 | `card_play_flow_test.gd`：自由技无 caster、M2 handler 一次执行、全体充能。 | M4 只展示结果。 |
| R-002 | `card_play_flow_test.gd`：专属 owner 从定义推导，冲突输入拒绝。 | — |
| R-003 | `card_play_flow_test.gd`：自由技原价/减费/0 费按实付 SP 充能。 | M6 可调数值，不改口径。 |
| R-004 | `card_play_flow_test.gd`：专属技原价/减费/0 费只给 owner 充能。 | 同上。 |
| R-005 | `deck_assembly_test.gd`：自由技多重列表逐份生成，同名副本身份独立。 | M5 实现奖励/购买写入列表。 |
| R-006 | `deck_assembly_test.gd`：主动专属技入牌库，骑士被动跳过但 N 保留。 | — |
| R-007 | `card_play_flow_test.gd`：潜影成功回手并连续打出。 | — |
| R-008 | `ultimate_card_test.gd`、`card_play_flow_test.gd`：消耗/成功次数只在成功后生效。 | 复制等新内容另行扩展。 |
| R-009 | `energy_rule_test.gd`：阈值即时清零生成，单事件只触发一次。 | — |
| R-010 | `energy_rule_test.gd`、`battle_card_session_test.gd`：未满入手、满手 draw top、生成不扣抽牌次数。 | — |
| R-011 | `ultimate_card_test.gd`：大招 0 SP、成功后消耗、不回能。 | — |
| R-012 | `hand_manager_test.gd`、`battle_card_session_test.gd`：首轮/后续轮新增尝试 `2+N`，不是补牌。 | M6 调整常数时保留新增抽语义。 |
| R-013 | `hand_manager_test.gd`、`battle_card_session_test.gd`：上限 7、失败不补抽。 | M4 验证 7 张布局。 |
| R-014 | `hand_manager_test.gd`、`battle_card_session_test.gd`：确定性重洗、同 seed 会话 trace、deck/combat/enemyPolicy 隔离。 | 完整共享 RNG golden 不属于 M3 聚焦 runner。 |
| R-015 | `hand_manager_test.gd`、`battle_card_session_test.gd`：实例守恒、先弃手再 M2、结算中新大招保留。 | — |
| R-016 | `card_play_flow_test.gd`、`battle_card_session_test.gd`：可连续出牌，只有显式结束回合推进 M2。 | M4 提供结束回合输入。 |
| R-017 | `deck_assembly_test.gd`、`battle_card_session_test.gd`：起始输入装配、洗牌与首抽。 | 初始技能/张数由 M5/M6 提供和调优。 |
| R-018 | 仅 `deck_assembly_test.gd`、`battle_card_session_test.gd` 证明“外部输入变化后的新战斗”牌库与 N 改变正确。 | M5 招募交易和 Run 写入尚未实现，parity 仍为“未开始”。 |
| R-019 | `enemy_skill_adapter_test.gd`、`round_resolver_test.gd` 与会话完整回归：敌方仍走旧规则和原 M2 顺序。 | 不迁入玩家卡牌系统。 |

## 测试证据

Godot：`4.7.1.stable.official.a13da4feb`。从 Godot 工程根执行：

```powershell
& $godot --headless --path . --log-file .godot\test-logs\m3-final-focused-20260904.log --script res://tests/run_m3b.gd
& $godot --headless --path . --log-file .godot\test-logs\m3-final-regular-20260904.log --script res://tests/run_regular_without_stability.gd
```

- M3 聚焦：`71 tests / 937 assertions / 0 failures`。
- 常规全量：`265 tests / 9720 assertions / 0 failures`。
- 按用户要求未运行 `m2_battle_stability_test.gd` 的 1000 场稳定性回归；常规 runner 明确输出 `OMITTED BY USER REQUEST`。这是主动省略，不是失败。
- M3 聚焦 runner 不加载完整共享 RNG golden；只保留卡牌层需要的同 seed 牌序与 deck/combat/enemyPolicy 流隔离。共享 `rng_test.gd` 未删除，仍由常规全量发现执行。

## M4 冻结入口与遗留风险

M4 可依赖的入口：`HandManager.start_battle_session`、`play_card`、`end_player_turn`、`session_snapshot` 与 `state_changed`/`command_finished` 信号；可依赖稳定 `CardRuntimeResult` code/details、`CardPlayRequest` 和 `BattleCardSession.snapshot`。UI 不应持有可变牌区数组或复制可用性/伤害规则。

仍需明确处理但不阻塞 M3 代码交接：

- `battleStart` 内容事件的最终 App/场景触发点尚未接入；不得在 M4 的 UI 与会话层各触发一次。
- 会话已提交失败后必须新建战斗会话恢复；M4 需要展示 fatal 状态，不能静默重试。
- 首轮 `2+N`、手牌上限 7 和充能系数仍是首版数值，最终手感与调整属于 M6。
- M5 必须把奖励/购买/招募的结果转换为下一场战斗的显式自由技多重列表与 roster；不能重新引入 `freeSlots` 或直接修改当前战斗牌区。
- 当前接口为无头逻辑冻结，不包含动画队列时长、拖拽取消、倍速或视觉验收。
