# M3 卡牌玩法总控任务书索引

## 文档状态

- 模块：Web → Godot 迁移 / M3 卡牌系统与新玩法
- 中枢：当前《弈者》卡牌玩法对话
- 状态：**M3 三批实现完成；`M3A_GATE` 与 `M3_FINAL` 独立 Review 均 PASS；等待项目总集成验收**
- 工程根：`C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版`
- 规则依据：仓库根 `AGENTS.md`、`docs/migration-plan.md`、本工程 `docs/m1-m2-handoff.md` 与 `docs/parity-checklist.md`

后续派工消息只需提供本任务书路径、指定任务书路径和（Review 时）审查模式，不再复述任务内容。执行者必须完整读取对应任务书后再行动。

## 范围确认

M3 负责纯无头卡牌运行时与玩家侧新玩法：卡牌定义/实例、牌库组装、抽牌/弃牌/消耗/重洗、出牌串行化、玩家 SP 支付与实付口径、新充能公式、大招卡生成、角色例外、战斗会话接线，以及 M3 规则冻结和交接。

M3 不负责：

- M4 战斗表现层、手牌 UI、拖拽/悬停、动画、倍速与视觉反馈。
- M5 奖励、商店、招募交易、Run 持久化等肉鸽流程。
- M6 数值调优或平衡裁决。
- 改写敌方旧式选技、SP、能量和大招规则。
- 顺手重构 M1/M2 已交付范围或清理用户的现有未提交改动。

## 当前基线与前置条件

- M0 RNG 与 M1 静态目录已存在；M2 已提供 29 个既有技能/能力 handler、敌方旧式 AI、棋子攻击/反应和回合结算。
- `autoload/hand_manager.gd` 仍是早期薄占位，M3 可将其改造成纯卡牌运行时的薄适配器。
- `RoundResolver` 目前仅报告 M3 deferred obligations；第三批负责用真实 M3 会话接线替换这些占位。
- 当前全量基线：224 tests / 9126 assertions / 0 failures；确定性稳定性 1000/1000。基线日志：`.godot/test-logs/headless-tests-20260904-114624-971-1328.log`。
- 工作树已有用户改动与未跟踪文件。所有执行者必须先后记录 `git status --short`，保留非本任务改动，禁止 reset/checkout/clean，禁止自行提交。
- Q1–Q7 按迁移计划 2026-09-01 首版默认决议执行。
- **Q8 已由用户于 2026-09-04 决议**：M3 首版暂时移除自由技 `basicDamage` 这张卡。它不进入卡牌目录、起始/Run 战斗牌库或玩家出牌桥，也不需要为卡牌玩法定义暴击率。为保持 M1/M2 基线与敌方兼容，本里程碑不删除底层技能定义或既有效果 handler；后续若恢复该卡，另行冻结其暴击口径。

因此：M3a/M3b 的规则前置决议均已满足；正式派工授权尚未给出，M3b 仍需等待 M3a Review PASS。

## 分批任务书

| 顺序 | 任务书 | 粗粒度产物 | 启动门禁 |
| --- | --- | --- | --- |
| 1 | `01_m3a_card_model_and_piles.md` | 卡牌定义/实例、独立 deck RNG、纯牌堆状态机、HandManager 薄适配 | 用户明确授权启动 |
| 2 | `02_m3b_card_play_energy_ultimate.md` | 出牌桥、SP 实付、效果单次调用、充能/大招、角色例外 | M3a Review PASS |
| 3 | `03_m3b_battle_session_and_freeze.md` | 牌库组装、完整回合接线、M3 obligations 落地、规则冻结交接 | M3-2 Review/中枢规则核对通过 |
| R | `90_m3_independent_review.md` | M3a 门禁审查与 M3 最终代码可行性审查 | 对应执行批完成 |

## 并行与顺序关系

```text
用户授权
   │
   ▼
M3-1 / M3a 牌堆内核
   │
   ▼
独立 Review：M3A_GATE
   │ PASS
   ▼
M3-2 / M3b 出牌、能量、大招
   │
   ▼
M3-3 / 战斗会话与冻结
   │
   ▼
独立 Review：M3_FINAL
   │ PASS
   ▼
中枢按规则条目与测试整合 M3 结论
```

- 三个实现批次存在共享文件与行为依赖，按顺序执行，不并行写代码。
- 独立 Review 可与中枢的玩法条目核对并行，但 Review 不与执行者同时修改生产代码。
- 同一执行 agent 优先连续承担 M3-1 至 M3-3，减少上下文损耗；Review 必须由未参与实现的 agent 承担。
- M3b 未冻结前，不得启动 M4 正式实现。

## 预计触碰的文件范围

预计新增：

- `data/definitions/card_*.gd`
- `data/catalogs/card_catalog.gd`
- `core/card_*.gd`
- `systems/cards/**`
- `tests/card_*.gd`、`tests/hand_manager_test.gd`、`tests/energy_rule_test.gd`、`tests/ultimate_card_test.gd`、`tests/deck_assembly_test.gd`、`tests/run_deck_test.gd`
- 独立 deck RNG 的测试/fixture
- `docs/m3-handoff.md`

预计修改：

- `autoload/hand_manager.gd`
- `core/rng.gd`（仅在无法通过现有 API 派生独立 deck 流时）
- `systems/combat/combat_ports.gd`
- `systems/combat/battle_runtime.gd`
- `systems/combat/round_resolver.gd`
- `systems/combat/piece_attack.gd`
- `systems/combat/piece_reactions.gd`
- 与上述接线直接相关的现有测试
- `docs/parity-checklist.md`

默认不应修改：`project.godot`、`tests/run_all.gd`、`tools/run_headless_tests.ps1`。若确需修改，执行者必须先在回报中说明理由并等待中枢确认。

## 总体接口与架构约束

1. 卡牌运行时状态是独立权威，不把手牌/牌堆塞进 M2 canonical `BattleState`。
2. `HandManager` 只做 Godot Autoload/场景适配；精确规则落在可无头实例化的纯 `HandRuntime`。
3. 卡牌目录从 M1 现有技能/英雄目录派生，不复制技能效果与数值成为第二事实源。
4. 每张运行时卡同时具有唯一 `instance_id` 与 `source_skill_id`；同名卡允许重复。
5. 洗牌只消费命名 `deck` RNG 流，不消费 `combat` 或 `enemyPolicy` 流。
6. `CardCombatBridge` 是唯一玩家出牌事务入口：验证 → 确定实付 SP → 支付 → 精确调用一次既有效果 → 决定去向 → 发出稳定事件/充能。
7. 卡牌层不得重复计算伤害或复制 M2 handler；敌方仍走旧式入口。
8. validator/preflight 拒绝必须零变更。效果已提交后若失败，必须显式报告 committed-prefix/fatal 并停止队列，不伪装回滚、不自动重试。

## 总体验收口径

- 执行者只回报实现证据，不自行宣布最终验收。
- 独立 Review 仅审查解析/运行风险、接口与路径、分层边界及指定测试可运行性。
- 玩法是否符合迁移计划，由模块中枢依据 R-001–R-019、Q1–Q8 和测试整合判断。
- 最终至少保持原有全量测试通过，并新增 M3 规则测试；任何已知失败必须列明测试名、原因和影响范围。
- M3a/M3b 聚焦 runner 不包含完整 RNG golden，也不运行 1000 场稳定性回归；只保留 deck 流与 combat/enemyPolicy 隔离、同 seed/同牌库确定性牌序等 M3 直接需要的 RNG 证据。共享 RNG 自身测试保留在原测试归属中。
