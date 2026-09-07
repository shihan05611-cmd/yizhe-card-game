# M4 战斗表现总控任务书索引

## 文档状态

- 模块：Web → Godot 迁移 / M4 战斗表现层
- 中枢：当前《弈者》战斗表现对话
- 状态：已获用户授权，按本索引分批执行
- 工程根：`C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版`
- 依据：仓库根 `AGENTS.md`、`docs/migration-plan.md`、本工程 `docs/m3-handoff.md` 与 `docs/parity-checklist.md`

## 范围与验收口径

M4 负责可直接完成一场战斗的 Godot 战斗场景、手牌交互、SP/能量、双方 2×3 棋盘、日志、伤害/治疗反馈、技能特效、自动战斗与 1x–4x 倍速。

M4 不负责 M5 肉鸽地图/奖励/商店/招募/Run 状态，不负责 M6 存档、批量模拟或平衡调参，不改变 M3 卡牌规则、M2 伤害规则与敌方规则。

美术验收只阻塞缺失、不可读、明显遮挡/溢出、错误状态与交互失效；像素级间距、颜色与最终风格细调留给整块完成后的用户人工调整。

所有动态视觉单元必须以 `.tscn` 场景或预置节点资源实例化。UI 脚本只做数据绑定、输入、调度和 Tween；禁止用 `_draw()`/`draw_*()` 或成片 `Control.new()`/`Label.new()` 拼出正式界面。

## 冻结前置

- `docs/m3-handoff.md` 已冻结 `HandManager.start_battle_session`、`play_card`、`end_player_turn`、`session_snapshot`、`CardPlayRequest` 与 `CardRuntimeResult`。
- `M3_FINAL` 独立 Review 为 PASS。
- 工作树包含大量 M1–M3 既有脏基线；所有执行者必须保留，不得 reset/checkout/clean，不得自行提交。
- 按用户要求，不运行 `m2_battle_stability_test.gd` 的 1000 场回归。

## 分批任务书

| 顺序 | 任务书 | 粗粒度产物 | 启动门禁 |
| --- | --- | --- | --- |
| 1 | `01_m4a_battle_bootstrap_and_presentation_contract.md` | 生产战斗组合根、只读 VM、Command、表现事件合同 | 用户已授权 |
| R1 | `90_m4_independent_review.md` / `M4_CONTRACT` | 合同与分层门禁 | M4-1 完成 |
| 2A | `02_m4b_battle_scene_board_hud.md` | 战斗场景、棋盘、HUD、日志、终局/fatal | M4_CONTRACT PASS |
| 2B | `03_m4c_card_hand_interaction.md` | 卡牌/手牌场景与交互 | M4_CONTRACT PASS |
| 2C | `04_m4d_skill_fx_catalog_and_scene_player.md` | 特效编排与节点播放器 | M4_CONTRACT PASS |
| 3 | `05_m4e_presentation_queue_floats_and_speed.md` | 表现队列、飘字、血条、倍速 | 2A/2B/2C 完成 |
| 4 | `06_m4f_auto_battle_e2e_and_visual_evidence.md` | 自动战斗、完整闭环、图形证据 | M4-5 完成 |
| R2 | `90_m4_independent_review.md` / `M4_FINAL` | 完整代码可行性 Review | M4-6 完成 |

## 并行与文件所有权

M4-1 与两次 Review 均串行。`M4_CONTRACT` PASS 后，M4-2、M4-3、M4-4 可并行：

- M4-2 独占 `scenes/battle/**` 与 `ui/battle/**`。
- M4-3 独占 `scenes/cards/**` 与 `ui/cards/**`。
- M4-4 独占 `data/presentation/**`、`scenes/effects/**` 与 `ui/effects/**`。
- 三批不得各自修改 `scenes/main.tscn`；最终组合由 M4-5/M4-6 统一完成。

执行者优先复用。Review 必须由未参与实现的 agent 承担，并保持只读。

## 共享接口约束

1. UI 只消费深拷贝 ViewModel，只发 Command，不持有或修改 `BattleState`/牌区数组。
2. 卡牌可用性必须由既有权威 validator/SP 预检派生，不在 UI 复制玩法条件。
3. 允许为 M4 增加无副作用的只读 inspection API，但不得改变成功结算、费用、充能、去向或回合顺序。
4. 表现事件必须带稳定 `event_id`、顺序号、批次、来源和视觉目标；不以节点引用作为领域数据。
5. 表现队列只控制播放与输入锁，不重复触发逻辑结算。
6. `battleStart` 内容事件只能由生产组合根触发一次。
7. fatal/committed failure 必须进入可见终止态，不能自动重试。
8. STR 只借鉴手牌布局和交互结构，不复制其 `Global`/`Signals`/`ActionHandler`/mod 隐式依赖。

## 总完成条件

- V-001–V-008、W-021–W-024、W-037 有实现与证据。
- 1200×700 下 7 张手牌不越界，悬停与拖拽可用。
- 玩家无需控制台即可开始并完成一场战斗。
- 1x 与 4x 使用同一逻辑结算次数和最终状态；4x 只压缩表现时长。
- 正式 UI/特效由场景节点实例化，静态守卫通过。
- M4 聚焦测试与常规非 1000 场回归通过；图形 smoke 留有同窗口证据。
- `M4_FINAL` 独立 Review PASS，并形成 `docs/m4-handoff.md`。
