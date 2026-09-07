# ART-2 战斗日志抽屉：默认隐藏、按键唤起

## 目标

把常年占着右侧 306×330、实际只有两三行内容的战斗日志改成抽屉：默认完全隐藏并把宽度归还战场，`Tab` 或顶栏按钮唤起，关闭期间用未读角标提示新日志。

## 允许范围

- `scenes/battle/combat_log.tscn`、`scenes/battle/combat_log_entry.tscn`、`ui/battle/combat_log.gd`
- **限定接线**：`ui/battle/battle_screen.gd`（抽屉开合、`_unhandled_input` 响应）与 `ui/battle/battle_hud.gd`（`%LogButton` 信号、角标 API）内新增函数与连接
- 本批专属的抽屉状态与角标测试

## 禁止范围

- 不得改动 ART-1 已冻结的节点树结构、既有函数签名与顶栏分组。
- 不修改 `scenes/battle/battle_screen.tscn`、`scenes/battle/battle_hud.tscn` 的节点增删（插槽由 ART-1 交付；确需微调必须回中枢，不得自行改）。
- 不修改 `scenes/cards/**`、`ui/cards/**`、`piece_slot`、结果层、fatal 层、`scenes/effects/**`、`ui/effects/**`。
- 不修改 `scenes/main.tscn`、`app/**`、`core/**`、`systems/**`。
- 不改 `project.godot`（`toggle_combat_log` 已由 ART-1 注册）。
- 不建 Theme、不统一色板、不改字阶。
- 不改变日志条目的数据来源与 VM 字段，不在 UI 侧过滤或重写日志文本。

## 依赖

- `ART_SKELETON` Review PASS。
- ART-1 已交付：`%LogDrawer`（`MainRow` 内定宽 300，默认 `visible = false` 且不占宽度）、`%LogButton`（顶栏右组 toggle 按钮 + 默认隐藏的角标子节点）、`toggle_combat_log` InputMap（主 `Tab`、备 `L`）。
- 现有 `CombatLog.bind_logs()`、`entry_nodes()`、`active_entry_count()` 语义保持不变，测试依赖它们。

## 实现要求

1. **默认隐藏**：默认状态是从布局里退出（`visible = false`），不是 `modulate.a = 0`、不是移出屏外。关闭时 `MainRow` 的战场区必须自动吃掉这 300px。
2. **双入口**：
   - `battle_screen.gd` 的 `_unhandled_input` 响应 `toggle_combat_log`；必须用 `_unhandled_input`，不得用 `_input`，避免与卡牌拖拽抢输入。
   - `%LogButton` 的 `toggled` 走同一个开合入口函数；按钮按下态始终反映抽屉真实开合，两个入口不得产生状态漂移。
3. **开合动画**：从右侧滑入/滑出，0.18s，`Tween.EASE_OUT`。动画期间不阻塞表现队列、不锁输入、不改变忙锁。快速连续切换必须能打断上一次 Tween，不留中间态。
4. **未读角标**：抽屉关闭期间 `bind_logs()` 带来新增条目时，`%LogButton` 角标显示未读数，上限显示 `99+`；打开抽屉即清零。抽屉打开状态下不累计。
5. **滚动**：条目从上往下追加，打开时自动滚到底部；用户手动上滚后，新条目不得强制把视口拽回底部。
6. **终局与 fatal**：不强制弹开或强制关闭抽屉，保持用户当前开合状态。
7. **条目复用**：沿用现有"节点复用 + `visible` 开关"的做法，不得每次绑定重建整棵条目树。
8. 抽屉内部内容区仍由 `.tscn` 实例化；不得用 `_draw()` 或成片 `Control.new()` 拼界面。

## 完成条件

- 启动后日志不可见，且 `MainRow` 战场区宽度确实增加了约 300（有断言，不只截图）。
- `Tab` 与 `%LogButton` 任一入口都能开合，两者状态同步；`L` 同样生效。
- 开合动画可被打断，连续切换后最终状态与按钮态一致。
- 关闭态下注入新日志 → 角标出现且数字正确；打开后角标归零；超过 99 条显示 `99+`。
- 打开态自动滚到底；手动上滚后新条目不抢滚动位置。
- 终局/fatal 下抽屉保持用户先前开合状态。
- 抽屉开合前后，表现队列事件数量、顺序与忙锁状态不变（有断言）。
- 测试跑通 `tests/run_m4_scene.gd`、`tests/run_m4.gd -- --skip-e2e`、`tests/run_regular_without_stability.gd`。
- 截图产出 `tests/artifacts/art1/01_default_log_hidden.png`（复拍确认）与 `02_log_opened.png`，并附一张带未读角标的状态图。
- 回报修改文件清单、测试输出与风险，不自行验收、不自行提交。
