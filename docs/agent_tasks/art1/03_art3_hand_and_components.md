# ART-3 手牌排布与组件信息结构

## 目标

治理手牌的重叠遮挡与上溢，并把棋子格、卡牌、结果层的信息结构收敛到可读密度，清除正式界面上的调试与占位残留。

## 允许范围

- `scenes/cards/**`、`ui/cards/**`
- `scenes/battle/piece_slot.tscn`、`ui/battle/piece_slot.gd`
- `scenes/battle/battle_result_overlay.tscn`、`ui/battle/battle_result_overlay.gd`
- `scenes/battle/fatal_overlay.tscn`、`ui/battle/fatal_overlay.gd`
- 本批专属的排布、边界与绑定测试

## 禁止范围

- 不修改 `scenes/battle/battle_screen.tscn`、`ui/battle/battle_screen.gd`、`battle_hud`、`board_grid`、`hero_energy_panel`、`combat_log`。
- 不修改 `scenes/main.tscn`、`app/**`、`core/**`、`systems/**`、`data/**`、`project.godot`。
- 不修改 `scenes/effects/**`、`ui/effects/**`。
- 不建 Theme、不统一色板、不改字阶、不补立绘。
- 不改变 `play_card_requested` 命令载荷、卡牌可用性判定来源与拖拽阈值语义；可用性仍只消费权威 `hand[].playable`，不在 UI 复制玩法条件。

## 依赖

- `ART_SKELETON` Review PASS。
- ART-1 已交付 `%HandLayer`：覆盖在 `MainRow` 下缘的 `Control`，`mouse_filter = PASS`，不参与高度分配；`HandReserve` 实心底板已删除。
- 现有 `apply_view_model()`、`set_interaction_state()`、`present_card_event()`、`cards_in_order()`、`bind_slot()`、`set_empty()` 语义保持不变，测试依赖它们。

## 实现要求

### 1. 手牌排布（A4）

现状 `hand_view.gd`：卡宽 168，`preferred_card_spacing = 126`，相邻重叠 42px 且后加入的压在前一张之上，导致左起六张的卡名与描述被压掉一半。

1. 卡面尺寸由 168×224 降为 **150×210**，`card_view.tscn` 的 `custom_minimum_size` 与内部子节点 offset 同步等比调整。
2. 扇形约束：7 张时整排总宽 ≤ 1000 并居中；相邻间距下限 = 卡宽 × 0.72（约 108），低于该值不再压缩间距，改为整体缩放。
3. 重叠时统一**左压右**（后面的卡在下），保证每张卡左侧 108px 始终完整可见。
4. 卡名、费用、类别必须落在左侧安全区或卡片顶部 56px 内，任何重叠状态下都可读。
5. **上溢约束**：`baseline_y + arc_height` 之后的**旋转外接框顶边**不得越过 `%HandLayer` 上界。保留现有四角断言，并把上界一并纳入。
6. hover：允许抬升并覆盖战场，抬升的卡必须整张可读（`scale 1.08` + 上移 28 + 投影 + 置顶），且**不改变其余卡片位置**（当前 hover 会把邻卡挤歪）。
7. 手牌数为 0 时底部不得出现任何可见框体。

### 2. 棋子格（B1）

1. `guard / warrior / archer` 是原始 key，正式界面走本地化名（守卫 / 战士 / 射手）；映射表放 UI 层常量，不回写数据层。
2. 无 buff 时该行隐藏，不留空行、不显示「无 Buff」。
3. `存活 / 已阵亡` 不再占一行文字：存活态不显示状态字；阵亡态整格置灰 + 标记 + 名称删除线。
4. HP 数字叠在血条上（居右），不再是「条 + 独立数字」横排两个控件。
5. 结果：每格从 4 行压到 2 行，格子高度由 76 降到约 64。
6. `present_hp_change()` / `present_pulse()` 的调用契约与动画时长语义不得改变。

### 3. 卡牌（B2）

1. 移除底部 `InstanceId`（当前显示「战斗卡牌」）——调试残留。
2. 描述区按 3 行预算重排（当前被截断成「同一 1200×700 窗…」）；超出用省略号，hover 时展开完整文本。
3. 费用底框 `corner_radius = 18` 配 38×38 方框不是正圆，改为 `radius = 半边长` 或换圆形节点。
4. `公共` / `弃牌` 两个贴边标签合并为底部一行的 tag 组。

### 4. 结果层与 fatal 层（B5）

1. 现状文字与按钮直接浮在暗底上、按钮无可见边界（06 截图）。加一块居中结果卡片：面板 + 描边 + 投影，标题 / 原因 / 主按钮三段式。
2. `重新开始演示战斗` 用与顶栏 `结束回合` 同一套主按钮观感（本批只做该按钮自身样式，不去读 ART-1 的 Theme）。
3. `fatal_overlay` 沿用同一版式，只换主色与图标。
4. 两层的输入锁定行为与 `restart_requested` 信号不变。

## 完成条件

- 0 / 1 / 7 张手牌三态：0 张时底部无可见框体；7 张时每张卡名、费用、类别可读，旋转外接框四角不越 `%HandLayer` 边界。
- hover 抬升后该卡整张可读，且其余卡片位置不变（有断言）。
- 拖拽阈值、`play_card_requested` 载荷、可用性锁定行为与改动前一致。
- 棋子格每格 2 行，空 buff 不占行，职业为中文，阵亡态可辨识；HP 数字叠在条上。
- 卡牌无 `战斗卡牌` 残留，描述 3 行内完整或省略号收尾，hover 可见全文。
- 结果层与 fatal 层为卡片式，主按钮有明确边界。
- 测试跑通 `tests/run_m4_hand_ui.gd`、`tests/run_m4_scene.gd`、`tests/run_m4.gd -- --skip-e2e`、`tests/run_regular_without_stability.gd`。
- 截图产出 `tests/artifacts/art1/03_hand_7.png`、`04_hand_0.png`、`05_hover_drag.png`、`06_result.png`。
- 回报修改文件清单、测试输出与风险，不自行验收、不自行提交。
