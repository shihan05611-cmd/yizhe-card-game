# ART 第一期独立 Review 任务书

## 角色与模式

Review 为只读角色，不修改实现。调用方必须指定以下一种模式：

- `ART_SKELETON`：ART-1 完成后的骨架与插槽门禁。
- `ART_FINAL`：ART-2 与 ART-3 完成后的完整代码可行性门禁。

输出结论只能是 `PASS`、`FAIL` 或 `BLOCKED`，并按严重度列 findings。

## 通用检查范围

- `AGENTS.md`、`docs/art-layout-revision.md`、`00_art_layout_index.md`、对应任务书。
- 当前 diff/工作树与执行回报。
- `scenes/**`、`ui/**`、`project.godot` 的 `[input]` 段、`tests/**`、`tests/artifacts/art1/**`。

## 通用禁止范围

- 不编辑任何文件，不提交。
- 不裁决玩法数值与平衡。
- 不以个人美术偏好阻塞。第一期只检查：缺失资源、不可读、遮挡、溢出、空洞（有框无内容）、错误态、交互失效、分层越界。
- 不对第二期项目（Theme、色板、字阶、立绘、FX 强度）提 FAIL。
- 不运行 `m2_battle_stability_test.gd` 的 1000 场回归。

## ART_SKELETON 检查项

1. `battle_screen.tscn` 与 Arena 内无残留 `layout_mode = 0` 的业务节点（全屏 anchor 的背景/反馈/覆盖层除外）。
2. `%LogDrawer`、`%HandLayer`、`%LogButton` 三个插槽存在、`unique_name_in_owner = true`，且 `%LogDrawer` 默认 `visible = false` 时不占 `MainRow` 宽度。
3. `HandReserve` 实心底板已删除；`%HandLayer` 为 `mouse_filter = PASS` 且不参与 VBox 高度分配。
4. 弈者条已并入各自棋盘上方，`hero_energy_panel` 的固定 `custom_minimum_size` 已移除且高度随人数自适应。
5. 顶栏三组分区成立；`SpeedLabel` 已移除而倍速选中态仍正确；`结束回合` 为唯一主按钮且 ≥ 120×44。
6. `toggle_combat_log` 已注册且含 `Tab` 与 `L` 两个事件；ART-1 未提前实现开合逻辑或角标。
7. 正式界面无 `2×3` 残留。
8. 未越界改动 ART-2/ART-3 的独占文件，未改 `scenes/main.tscn` 与规则层。
9. 三档窗口（1200×700 / 1280×720 / 1600×900）截图存在且无溢出、裁切、单侧死空隙。
10. `tests/run_m4_scene.gd`、`tests/run_m4.gd -- --skip-e2e`、`tests/run_regular_without_stability.gd` 可运行且通过。

Review 结果写入 `docs/agent_tasks/art1/reviews/ART_SKELETON-review.md`。

## ART_FINAL 检查项

1. 场景/脚本解析、NodePath、资源路径、主场景与 autoload 可行。
2. 日志抽屉：默认隐藏且宽度确实归还战场；`Tab`、`L`、`%LogButton` 三个入口状态同步；响应挂在 `_unhandled_input` 而非 `_input`；Tween 可打断；未读角标计数与 `99+` 上限正确；终局/fatal 不强制改变开合。
3. 手牌：0/1/7 三态正确，0 张无可见框体，7 张时旋转外接框四角不越 `%HandLayer` 边界，卡名/费用/类别在重叠下可读，hover 不移动邻卡。
4. 交互合同未变：拖拽阈值、`play_card_requested` 载荷、可用性仍只消费权威 `hand[].playable`，UI 未复制玩法条件。
5. 表现层未被污染：抽屉开合与手牌重排不调用逻辑层，不改变表现队列事件顺序、数量与忙锁。
6. 动态视觉单元仍由 `.tscn` / `PackedScene.instantiate()` 产出；无正式 `_draw()`/`draw_*()` 或成片 `Control.new()`。
7. 调试与占位残留已清除：`战斗卡牌`、`2×3`、`无 Buff` 空态、`guard/warrior/archer` 原始 key。
8. 棋子格压到 2 行且 `present_hp_change()` / `present_pulse()` 契约未变。
9. 结果层与 fatal 层为卡片式版式，输入锁定与 `restart_requested` 行为未变。
10. `tests/artifacts/art1/` 的 8 张证据齐备且与实现一致，未把未跑的项伪报为通过。
11. 指定测试命令全部可运行并通过；工作树既有脏基线被保留，执行者未自行提交。

Review 结果写入 `docs/agent_tasks/art1/reviews/ART_FINAL-review.md`。

## 回报格式

- 模式与结论。
- Findings（文件/行、风险、建议）。
- 实际运行的命令、退出码、测试/断言数字。
- 范围审计、未覆盖项和环境限制。
- PASS 时明确写出下一门禁可启动；FAIL/BLOCKED 时写出最小修复范围。
