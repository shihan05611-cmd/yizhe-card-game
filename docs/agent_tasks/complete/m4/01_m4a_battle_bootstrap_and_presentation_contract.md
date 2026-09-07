# M4-1 生产战斗组合根与表现合同

## 目标

在不改变 M1–M3 玩法规则的前提下，提供 M4 场景可直接消费的生产战斗启动入口、深拷贝 ViewModel、卡牌无副作用可用性查询、Command 入口和稳定表现事件合同。

## 允许范围

- `app/**`
- `autoload/game_root.gd`、`autoload/signals.gd`、`autoload/hand_manager.gd`
- 对 `systems/cards/card_combat_bridge.gd`、`systems/combat/battle_runtime.gd`、`systems/cards/battle_card_session.gd` 做最小、向后兼容、只读 inspection API 增补
- 与本合同直接相关的 `tests/**`
- `docs/parity-checklist.md` 对应条目证据

## 禁止范围

- 不创建正式战斗/卡牌/特效场景。
- 不修改费用、充能、validator、伤害、Buff、去向、抽牌或回合顺序。
- 不实现 M5 Run 数据或存档。
- 不从测试 fixture 直接引用生产代码；可以参照其装配形状后建立自己的生产入口。

## 依赖

- 完整读取 `00_m4_battle_presentation_index.md`、`docs/m3-handoff.md`。
- 阅读 `HandManager`、`BattleCardSession`、`CardCombatBridge`、`BattleRuntime`、`BattleState`、M3 相关测试与 `tests/support/m3_card_fixture.gd`。

## 实现要求

1. 建立 M4 生产战斗 bootstrap/controller，使用真实 `ContentCatalog`、真实 M2/M3 runtime 和显式首版 roster/free-skill 输入启动一场独立战斗。
2. `battleStart` 由组合根单点触发；重复初始化不得双触发。
3. ViewModel 至少包含：会话状态、round/phase/result、共享 SP、双方六槽棋子、玩家/敌方弈者及能量、四牌区计数、手牌顺序、卡牌名称/说明/类别/owner/费用/去向/可用性与不可用原因、日志和 pending presentation events。
4. ViewModel 必须深隔离；外部修改不得影响权威状态。
5. 卡牌可用性检查复用与真实出牌相同的预检权威，并证明查询不扣 SP、不移动卡、不写成功次数、不消费 RNG、不产生事件。
6. Command 仅暴露 `play_card(instance_id)`、`end_player_turn()`、倍速设置和后续自动战斗开关的接口形状；牌堆原始 mutation 不暴露给 UI。
7. 表现事件统一为 JSON-safe 数据，至少含 `sequence`、`batch_id`、`event_id`、`source`、`visual_target`、`payload`；覆盖 damage/buff/round/card/log/fatal。
8. W-021–W-024 的稳定视觉定位由此合同或适配器建立，不把 Node 引用塞入领域层。

## 完成条件

- 新增 `battle_view_model_test.gd` 与 `combat_presentation_event_test.gd`，覆盖深隔离、队伍总生命百分比、六槽定位、卡牌展示/可用性查询零副作用、事件目标/来源/批次。
- bootstrap 可在无头测试中启动真实会话，执行出牌和结束回合 Command。
- fatal Result 会进入可见 VM 状态且停止后续 Command，不自动重试。
- M3 聚焦与常规非稳定性回归仍通过。
- 未运行 1000 场回归。
- 回报修改文件、测试命令/数字、接口说明、已知风险；不自行验收或提交。
