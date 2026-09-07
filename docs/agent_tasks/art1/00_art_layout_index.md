# ART 第一期（战斗界面布局）总控任务书索引

## 文档状态

- 模块：Godot 战斗表现层 / 美术第一期（布局与信息结构）
- 中枢：当前《弈者》战斗表现对话
- 状态：已获用户授权，按本索引分批执行
- 工程根：`C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版`
- 依据：仓库根 `AGENTS.md`、本工程 `docs/art-layout-revision.md`、`docs/m4-handoff.md`
- 现状证据：`tests/artifacts/m4/01~06`

## 范围与验收口径

第一期只处理**布局与信息结构**：根布局容器化、战斗日志抽屉化（默认隐藏、按键唤起）、手牌区去固定底板与重叠遮挡治理、弈者面板并栏、棋子/卡牌/顶栏/结果层的信息结构收敛，以及正式界面上残留的调试字样清除。

第一期**不做**：全局 Theme 资源、色板统一、字阶收敛、立绘补齐与统一裁切、FX 强度调整。这些是第二期，`docs/art-layout-revision.md` 的 P2 已登记。

第一期**不碰**：`core/**`、`systems/**`、`app/**` 的规则与合同，`BattlePresentationQueue` 的时钟与忙锁，ViewModel / Command / 表现事件的字段与语义。所有改动落在 `scenes/**`、`ui/**` 与 `project.godot` 的 InputMap。

验收只阻塞：缺失资源、不可读、遮挡、溢出、空洞（有框无内容）、错误态与交互失效。像素级间距与颜色属于第二期，不在本期裁决。

沿用 M4 既有约束：所有动态视觉单元必须由 `.tscn` / `PackedScene.instantiate()` 产出；UI 脚本只做绑定、输入、调度与 Tween，禁止 `_draw()` / 成片 `Control.new()` 拼正式界面。

## 现状根因（三条，其余问题多为派生）

1. 整屏是绝对坐标拼的。`battle_screen.tscn` 的 HUD / Arena / CombatLog / HandReserve 全部 `layout_mode = 0` + 手写 offset，Arena 内部同样；而 `project.godot` 是 `canvas_items` + `expand` 拉伸，非 1200×700 的窗口只会留白或裁切，不会重排。
2. 右侧两栏"先占位再填内容"。日志固定 306×330，弈者面板固定 194×150×2，实际常年只有 2 行日志、1 名弈者，右半屏长期空着。
3. 手牌区是固定实心底板。`HandReserve` 1160×248，无手牌时是大空框（06 截图），满手牌时卡片从上沿溢出压住 Arena（01/02 截图）。

## 分批任务书

| 顺序 | 任务书 | 粗粒度产物 | 启动门禁 |
| --- | --- | --- | --- |
| 1 | `01_art1_layout_skeleton_and_topbar.md` | 根布局容器化、弈者并栏、顶栏三分组、抽屉/手牌层插槽、InputMap 注册 | 用户已授权 |
| R1 | `90_art_independent_review.md` / `ART_SKELETON` | 骨架与插槽合同 | ART-1 完成 |
| 2A | `02_art2_combat_log_drawer.md` | 日志抽屉：默认隐藏、按键唤起、未读角标 | ART_SKELETON PASS |
| 2B | `03_art3_hand_and_components.md` | 手牌排布、棋子格、卡牌、结果层 | ART_SKELETON PASS |
| R2 | `90_art_independent_review.md` / `ART_FINAL` | 完整代码可行性 Review | 2A/2B 完成 |

## 并行与文件所有权

ART-1 与两次 Review 串行。`ART_SKELETON` PASS 后 ART-2 与 ART-3 可并行，所有权互不相交：

- **ART-1 独占**：`scenes/battle/battle_screen.tscn`、`ui/battle/battle_screen.gd`、`scenes/battle/battle_hud.tscn`、`ui/battle/battle_hud.gd`、`scenes/battle/board_grid.tscn`、`ui/battle/board_grid.gd`、`scenes/battle/hero_energy_panel.tscn`、`ui/battle/hero_energy_panel.gd`、`project.godot` 的 `[input]` 段。
- **ART-2 独占**：`scenes/battle/combat_log.tscn`、`scenes/battle/combat_log_entry.tscn`、`ui/battle/combat_log.gd`；另**限定**允许在 `ui/battle/battle_screen.gd` 与 `ui/battle/battle_hud.gd` 内新增抽屉开合与角标接线，不得改动 ART-1 已定的节点树与既有函数签名。
- **ART-3 独占**：`scenes/cards/**`、`ui/cards/**`、`scenes/battle/piece_slot.tscn`、`ui/battle/piece_slot.gd`、`scenes/battle/battle_result_overlay.tscn`、`ui/battle/battle_result_overlay.gd`、`scenes/battle/fatal_overlay.tscn`、`ui/battle/fatal_overlay.gd`。
- 两批都不得修改 `scenes/main.tscn`。

执行者按模块复用，不要一味新起 agent。Review 由未参与实现的 agent 承担并保持只读。

## 共享接口约束（ART-1 必须先冻结，2A/2B 只消费）

1. `%LogDrawer`：`MainRow` 内的定宽 300 容器，ART-1 交付时 `visible = false` 且不占布局宽度；ART-2 只在其内部填内容并实现开合动画。
2. `%HandLayer`：覆盖在 `MainRow` 下缘的 `Control`，`mouse_filter = PASS`，不参与 VBox 高度分配；ART-3 只在其内部排手牌。
3. `%LogButton`：顶栏右组的 toggle 按钮，ART-1 交付时已存在且无接线；ART-2 接它的 `toggled` 与角标 API。
4. `toggle_combat_log` InputMap action（主 `Tab`、备 `L`）由 ART-1 注册；ART-2 在 `_unhandled_input` 响应，不得用 `_input` 抢卡牌拖拽。
5. 日志开合、手牌重排都不得调用逻辑层，不得改变表现队列的忙锁与事件顺序。
6. 顶栏、棋盘、弈者条、日志按钮的对外 API 保持"绑定 VM + set 状态"的既有形态，不新增 UI 侧玩法判断。

## 总完成条件

- 1200×700 / 1280×720 / 1600×900 三档窗口下无溢出、无裁切、无空洞。
- 日志默认隐藏且不占宽度；`Tab` 与顶栏按钮均可唤起；关闭期间有未读角标。
- 0 / 1 / 7 张手牌三态正常：无手牌时底部无可见空框；7 张时每张卡名与费用可读、不越界。
- 正式界面无 `2×3`、`战斗卡牌`、`guard/warrior/archer`、`无 Buff` 空态等调试或占位残留。
- 结果层与 fatal 层为卡片式版式，主按钮有明确样式。
- `tests/run_m4_scene.gd`、`tests/run_m4_hand_ui.gd`、`tests/run_m4.gd -- --skip-e2e`、`tests/run_regular_without_stability.gd` 全部通过。
- `tests/artifacts/art1/` 留下 8 张证据截图。
- `ART_FINAL` 独立 Review PASS，并更新 `docs/art-layout-revision.md` 的完成状态。

## 命令基线

```powershell
$godot = 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
& $godot --headless --path . --log-file .godot\test-logs\art1-scene-<stamp>.log --script res://tests/run_m4_scene.gd
& $godot --headless --path . --log-file .godot\test-logs\art1-hand-<stamp>.log --script res://tests/run_m4_hand_ui.gd
& $godot --headless --path . --log-file .godot\test-logs\art1-focused-<stamp>.log --script res://tests/run_m4.gd -- --skip-e2e
& $godot --headless --path . --log-file .godot\test-logs\art1-regular-<stamp>.log --script res://tests/run_regular_without_stability.gd
```

按用户要求，不运行 `m2_battle_stability_test.gd` 的 1000 场回归。截图捕获沿用 `tests/capture_m4_visual_evidence.gd` 的方式，新增脚本输出到 `tests/artifacts/art1/`。
