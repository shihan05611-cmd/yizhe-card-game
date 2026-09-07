# ART-1 战斗界面骨架容器化与顶栏重排

## 目标

把战斗界面从手写 offset 的绝对布局改为容器驱动的响应式骨架，取消"先占位再填内容"的右侧竖栏，重排顶栏信息分组，并为日志抽屉与手牌层冻结插槽合同。本批交付后，界面在三档窗口尺寸下都应自然重排，且不再出现死空隙。

## 允许范围

- `scenes/battle/battle_screen.tscn`、`ui/battle/battle_screen.gd`
- `scenes/battle/battle_hud.tscn`、`ui/battle/battle_hud.gd`
- `scenes/battle/board_grid.tscn`、`ui/battle/board_grid.gd`
- `scenes/battle/hero_energy_panel.tscn`、`ui/battle/hero_energy_panel.gd`
- `scenes/battle/hero_energy_item.tscn`、`ui/battle/hero_energy_item.gd`（仅尺寸与占位框统一，不做立绘补齐）
- `project.godot` 的 `[input]` 段
- 本批专属的布局与实例化测试

## 禁止范围

- 不修改 `core/**`、`systems/**`、`app/**`、`data/**`。
- 不修改 `scenes/main.tscn`。
- 不修改 `scenes/cards/**`、`ui/cards/**`、`scenes/battle/piece_slot.tscn`、`ui/battle/piece_slot.gd`、`scenes/battle/combat_log*.tscn`、`ui/battle/combat_log.gd`、结果层与 fatal 层。
- 不实现日志抽屉的开合逻辑与角标（属 ART-2），本批只留插槽。
- 不实现手牌排布算法改动（属 ART-3），本批只留 `%HandLayer`。
- 不建 Theme 资源、不统一色板、不改字阶、不补立绘、不动 FX。
- 不改变 ViewModel 字段消费方式，不在 UI 侧新增玩法判断。

## 依赖

- 用户已授权本期。
- 现状证据 `tests/artifacts/m4/01_battle_ui_7_cards.png`、`06_battle_result.png`。
- 现有 `bind_view_model` / `bind_team` / `bind_heroes` / `set_input_locked` / `set_queue_busy` / `set_speed_display` 等对外 API 语义保持不变。

## 实现要求

### 1. 根布局容器化（A1）

1. `BattleScreen` 改为 `MarginContainer(边距 16) → VBoxContainer(separation 12)`，三段：`TopBar` / `MainRow` / 覆盖层。
2. `MainRow` 用 `HBoxContainer`：战场区 `size_flags_horizontal = EXPAND_FILL` + `%LogDrawer`（定宽 300）。
3. 删除 `BattleScreen` 与 `Arena` 内所有手写 offset，全部改用容器 + `custom_minimum_size` + `size_flags`；不允许保留 `layout_mode = 0` 的业务节点（`Background`、`FeedbackLayer`、覆盖层等全屏 anchor 节点除外）。
4. 删除 `HandReserve` 这块实心 Panel 底板，改为 `%HandLayer`：覆盖在 `MainRow` 下缘的 `Control`，`mouse_filter = PASS`，不参与 VBox 高度分配；底部视觉压底改为一层自上而下的渐隐暗色（高度约 200，`mouse_filter = IGNORE`），不画边框。
5. z 序自低到高：背景 → 战场 → 手牌层 → 日志抽屉 → `FeedbackLayer`/FX → 结果层 → fatal 层。

### 2. 弈者面板并入棋盘，取消第三栏（A5）

1. `AllyHeroes` / `EnemyHeroes` 不再是 Arena 右侧独立竖栏，改为贴在各自棋盘正上方，与棋盘同宽。
2. 高度随人数自适应：移除 `hero_energy_panel.tscn` 上的固定 `custom_minimum_size`，用 `VBoxContainer` 自然撑开；一名弈者时不得留出多余空面板。
3. `MainRow` 最终只剩「我方列 / 敌方列 / 日志抽屉」；日志关闭时是干净的左右对称双列。
4. `hero_energy_item.tscn` 的立绘框与占位框必须同尺寸、同圆角、同描边；补图前敌方保留占位，但不得出现"一边方块一边满铺贴图"的不一致。本批不生成新美术。

### 3. Arena 与棋盘余白统一（A6）

1. 棋盘底边到容器底边现有约 30px 的单侧死空隙必须消除，改由 `separation` 统一。
2. 我方与敌方两块棋盘的标题、外框、内边距完全镜像一致，只有主色不同。

### 4. 顶栏三分组（B3）

1. 顶栏改为三组，组内紧凑、组间留白：
   - 左：回合、SP（SP 用条 + 数字，不再是纯文本）
   - 中：牌堆 抽/手/弃/耗，四个图标位 + 数字，不再是一整句文本
   - 右：倍速段控件、自动开关、`%LogButton`、结束回合
2. 删除 `SpeedLabel`（那个「1x」）——它与四个倍速按钮的选中态重复表达同一件事，只保留段控件高亮。`set_speed_display()` 保留并继续同步按钮选中态。
3. `结束回合` 是全屏唯一主按钮，尺寸不小于 120×44，对比度明显高于其余控件。
4. `%LogButton` 本批只建节点（`toggle_mode = true`，含未读角标子节点，默认隐藏），不接任何逻辑；ART-2 负责接线。

### 5. 调试字样清除（B4）

1. 棋盘标题里的 `2×3` 是规格调试信息，正式界面去掉，只留「我方 / 敌方」。

### 6. InputMap 注册

1. `project.godot` 新增 action `toggle_combat_log`，主键 `Tab`，备用键 `L`。本批只注册，不响应。

## 完成条件

- 所有被改场景可单独实例化，无缺失 NodePath、脚本或资源。
- `%LogDrawer`、`%HandLayer`、`%LogButton` 三个插槽存在且 `unique_name_in_owner = true`；`%LogDrawer` 默认 `visible = false` 且关闭时不占 `MainRow` 宽度。
- 1200×700 / 1280×720 / 1600×900 三档窗口截图：无溢出、无裁切、无单侧死空隙，右半屏不再有长期空白竖栏。
- 一名弈者与多名弈者两种 VM 下，弈者条高度自适应且无多余空面板。
- 正式界面不再出现 `2×3`。
- 顶栏三组分区可见，`SpeedLabel` 已移除且倍速切换仍能正确高亮。
- `toggle_combat_log` 在 InputMap 中存在且含 `Tab` 与 `L` 两个事件。
- 测试：新增/更新布局断言（插槽存在性、抽屉关闭不占宽、三档尺寸下关键控件矩形不越界、弈者条自适应），并跑通 `tests/run_m4_scene.gd`、`tests/run_m4.gd -- --skip-e2e`、`tests/run_regular_without_stability.gd`。
- 截图产出 `tests/artifacts/art1/01_default_log_hidden.png`、`07_1600x900.png`、`08_1280x720.png`。
- 回报修改文件清单、测试输出与明显布局风险，不自行验收、不自行提交。
