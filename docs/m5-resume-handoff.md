# M5 肉鸽层跨设备接力说明

## 当前状态

- 暂停日期：2026-09-07。
- 用户要求在 M5-03 完成后暂停，后续换设备接力。
- 已完成：M5-01 Run 契约与事务随机、M5-02 地图与遭遇、M5-03 Run 生命周期。
- 尚未开始：M5-04 经济与非战斗节点、M5-05 战斗桥接与进度提交、M5-06 神通休眠迁移与完整通关、M5-90 独立 Review。
- 暂停时没有启动 M5-04，也没有启动最终 Reviewer。

## 已冻结的产品边界

- 免费技能以 `free_skill_ids` 多重集持有，允许重复；不迁移 Web 的 `equippedFreeSkillIds`、技能槽切换或槽位直放技能。
- 开局从零神机免费技能中抽取两张不同技能，各加入一张。
- 精确英雄站位由 `hero_deployment_slots` 保存；`front_hero_ids`、`back_hero_ids` 只是按槽位排序的行视图。
- 神通 `charge`、`assault`、`sacrifice` 的代码后续仍需迁移和独立测试，但暂不接入 Run、GameRoot、BattleController、UI 或玩家流程。
- `shentongAssaultBurst`、`shentongChargeOverload` 保留目录和效果代码，但不得进入奖励池、商店池或实际 Run。
- 普通遗物仍需在 M5-04/M5-05 接入。
- M6 存档、恢复、批量模拟和平衡不属于 M5；禁止 1000 次回归。

## 已完成实现

### M5-01

- `systems/roguelike/run_contract.gd`：闭合、JSON-safe 的纯内存 Run 权威状态。
- `systems/roguelike/run_random_transaction.gd`：与 Web 等价的重放队列事务随机；失败不倒退底层 RNG。
- `autoload/run_state.gd`：只持有状态并薄转发 reset/snapshot/transition。
- 可恢复领域失败必须返回 `false` 或 `command_error(...)`；GDScript VM 级错误无法像 JavaScript `throw` 一样被适配器捕获。

### M5-02

- `systems/roguelike/map_system.gd`：三章 `3×10` 地图、相邻行连边、前沿、类型权重、遭遇预算和六槽展开。
- `tests/fixtures/web_m5_map_golden.json`：来自当前 Web 源码的三章 90 节点金标、遭遇金标和真实 weighted-pool 探针。
- 默认三章均为 `fixedByRow`，所以默认地图类型不消耗 RNG；weighted 分支由额外 Web 探针覆盖。

### M5-03

- `systems/roguelike/run_lifecycle.gd`：无神通开局、初始四选一、地图前沿、节点进入／完成、招募、部署、三章推进、failed/cleared/quit。
- `hero_deployment_slots` 使用英雄 ID 字符串到唯一 `1..6` 槽位的 JSON-safe 映射。
- 商店、锻造、事件在本批只进入相应状态；`shop_options` 保持为空，不改货币或结算效果。
- `complete_current_battle()` 只是无战斗世界依赖的生命周期入口；M5-05 必须在真实战斗事务成功后调用。
- 当前胜利会直接进入招募或推进；M5-04/M5-05 接入战后奖励时需要在该入口前插入 reward 阶段。

## 暂停前测试证据

- M5-01 聚焦：10 tests / 86 assertions / 0 failures。
- M5-02 聚焦累计：17 tests / 1238 assertions / 0 failures；Web 地图基准 4/4。
- M5-03 聚焦累计：23 tests / 1497 assertions / 0 failures。
- 暂停前常规非稳定性套件：346 tests / 12444 assertions / 0 failures。
- 生产架构违规：0。
- Godot 4.7.1 editor parse：exit 0。
- `git diff --check`：无输出。
- 未运行 `m2_battle_stability_test.gd` 的 1000 次回归；独立 auto battle E2E 仍按既有入口分离。
- 日志中的 Windows 根证书读取失败和无法写全局 editor settings 是环境提示，不影响测试及解析退出码。

## 接力步骤

1. 完整读取仓库外层 `AGENTS.md`、`docs/migration-plan.md`、本文件和 `docs/agent_tasks/m5/README.md`。
2. 检查当前分支、提交与工作区，确认 M5-01～03 文件完整。
3. 从 `docs/agent_tasks/m5/M5-04-economy-nodes.md` 启动同一 Executor 风格的继续执行。
4. M5-04 完成后依次执行 M5-05、M5-06；不要提前把休眠神通接入游戏。
5. 全部实现完成后，才启动与 Executor 独立的 M5-90 Reviewer。

## 下一批特别注意

- 免费技能奖励与商店允许获得已有技能的额外副本。
- `tradePermit` 出售技能时只移除一张副本。
- `shentongEvolve` 类两件遗物必须在奖励和商店候选池中显式过滤并由测试锁定。
- 选项必须采用权威快照；伪造、陈旧或重复提交不得改变 Run 状态或事务随机序列。
