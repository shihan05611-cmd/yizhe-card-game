# 墨玉棋境战斗界面接入记录（2026-09-09）

## 本次变更

将 `tools/art/battle-concept.html` 的墨玉、暖纸和克制金色语言接入 Godot 战斗界面，同时继续使用实际战斗 View Model、卡牌校验、事件队列和 Run 入口。

- 战场改为共享的墨玉棋盘：原生代码绘制背景、石板边缘、河界、阵列线与角饰；双方六格继续由真实 `teams.ally/enemy.slots` 驱动。
- 沿用现有 `GeometryPiece` 的四种棋子原生绘制，保留敌我色彩、朝向和弩箭出手表现。棋子格仍显示真实生命、状态、死亡和目标锚点。
- 新增原生代码绘制的手牌纸面、费用玉印、技能插图、SP 圆环和立绘光晕；这些节点全部忽略鼠标输入，卡牌仍经现有 `InputButton → CardView → HandView` 拖拽流程提交。
- HUD 调整为中心回合/阶段、左侧 SP 与牌堆信息、右侧暖金结束回合；战斗日志保持抽屉覆盖，不挤压棋盘。
- 弈者栏以真实 `heroes.ally/enemy` 数组生成，支持 1–3 名弈者及各自的能量条、肖像和大招归属。敌方肖像方向继续使用现有占位规则；是否为没有对应立绘的敌方角色提供专用肖像，待用户确认。
- 灼烧改为附着在棋子上的 `BurnAura` 代码绘制，按 buff 事件的层数快照更新；空位、死亡、重开和暂停均清理或停止该表现。
- 普攻展示改用仅存在于表现流的 `presentation_action_id`：同一击的反馈不会重复启动出手；列攻击、额外行动、追击、反击及跨 batch 的边界由事件流和回归用例覆盖。该 ID 不进入伤害或效果上下文。
- 棋子主命中表现时长调整为 440ms；队列保持 1×/4× 的四比一关系。切速在下一个表现段生效，当前段的灼烧、棋子动作和队列继续使用同一活动段速度。
- 伤害/治疗浮字先停留于命中点，再上浮和淡出；中断后的棋子 Pulse 会回落到由存活状态确定的稳定颜色，避免残留中间色。

本轮不改变卡牌玩法：拖过阈值才请求出牌，短拖不会提交；点击不会因为视觉接入而绕过既有卡牌校验。HTML 概念稿中的“点卡选目标”、示例数值、满手切换和重置按钮均未接入产品玩法。

## 已完成验证

- motion 回归：18 tests / 133 assertions 通过，覆盖单出手 ID、攻击边界、灼烧生命周期、440ms 的 1×/4× 时长、浮字停留、Pulse 复位与暂停路径。
- layout 回归：17 tests / 481 assertions 通过，覆盖战场、卡面、HUD、1–3 弈者和不同手牌数的布局合同。
- 实窗口取证：真实 Run 的短拖不提交、长拖只提交一次已通过；截图取证覆盖界面构图和拖拽路径。
- 真实 Controller 单回合：1× 与 4× 产生相同的 settlement snapshot。该验证只说明该单回合结算结果相同，不能替代完整 Run 的状态一致性验证。
- M4 E2E：5 tests / 1715 assertions / 0 failures，日志为 `.godot/test-logs/four-piece-final-e2e.log`。自动战斗在 1× 为 158.300s、4× 为 39.575s，比例为 4.000；两次均提交 46 条命令并产生 780 条事件。
- Windows Portable Pack 已成功导出到 `build/YizheCardGame`；从导出的 PCK 以 headless 启动并以退出码 0 结束。导出末尾仍有沙箱无法保存系统 `editor_settings` 的提示，另有机器根证书提示；未见脚本或资源错误。

最终常规回归：405 tests / 14412 assertions / 0 failures，日志为 `.godot/test-logs/four-piece-verified-regular.log`。该既有常规脚本按约定省略 `m2_battle_stability_test`；M4 E2E 已单独完成。

## 静态审查与验证边界

- 当前审查未发现 `charge`、`assault`、`sacrifice` 被重新接入战斗场景、卡牌输入或 Run HUD；它们仍留在休眠实现与数据中。
- 当前切速路径将 HUD 立即更新，但灼烧使用队列的活动段速度；下一事件开始再次同步，因此不会让当前段的灼烧与出手 Tween 使用不同倍率。
- 本轮未追加千局稳定性测试，也未穷举完整 Run 的所有分支；敌方专用肖像的风格待用户确认。

## 归属说明

本轮新增的代码绘制组件由 GPT-6 完成，Terra 完成了相应接入和专项实现；收口阶段的阵容模态及遗物场景接线由 root 接手完成。记录只覆盖本次墨玉战斗界面、其表现时序和相应验证；工作区已有的 Run 存档、肉鸽流程、随机事务、文档及其他未提交修改不归入本轮美术接入。

## 用户反馈后的补充修复

- 移除 generic 技能的蓝圈占位表现，保留既有 FX 生命周期；已定义技能改为短命中的铜色刻线/锁定角和玉色状态标记，并消除旧图形向右下偏移半尺寸的问题。该部分由 GPT-6 完成，FX 专项为 9 tests / 109 assertions 通过。
- 阵列视觉顺序调整为 1–3 靠中线前排、4–6 后排：ally 为 `[4,1] / [5,2] / [6,3]`，enemy 为 `[1,4] / [2,5] / [3,6]`。这是纯 `Control` 排序，未修改单位 ID 或 View Model；Terra 专项为 1 test / 38 assertions 通过，`run_art_layout` 为 17 tests / 481 assertions 通过。
- 卡面继续以短句展示规则，完整说明保留在现有 tooltip；灼烧近景截图可作为补充展示，不是额外的玩法验收路径。
- 用户选择的等待牌采用“结束回合按钮旁：小幅叠牌，只展开队首”。同一实例不会重复进入队列；等待中的牌可取消，取消不扣 SP 且回到手牌。队首沿用原有 guard 校验，通过后才提交；失效 guard 会提示并退回，暂停时 deferred pump 不提交，终局清空等待项。

上述两项修复已更新进入 Windows Portable Pack。`build/YizheCardGame/logs/formation-fx-smoke.log` 记录导出 PCK 启动退出码 0，未见脚本或资源错误；仍有机器根证书提示。

非 headless 截图取证已完成且 `failures=0`；目检更新后的 `tests/artifacts/inkjade/05_1200_three_heroes_mixed_six.png`，双方前排 1/2/3 均位于中线一侧。

## 四棋子阵型、遗物与待出牌补充

- Run 的默认棋阵改为 `[shield, null, null, assassin, crossbow, banner]`：1 号甲卒、4 号刺客、5 号机弩、6 号旗兵，2/3 留空。每类棋子库存为两枚；地图模态支持拖拽换位或用库存替换，替换不增加上阵人数。旧 checkpoint v1 升级为 v2 时保留原有六人阵列数据。
- 本轮未手动修改宁不凡或千机的数值。阵型变更只调整默认部署、库存与界面投影。
- HUD 顶部以无边框横排展示实际持有遗物，覆盖当前可获得的 20 种遗物；View Model 使用真实 owned relic ID 映射出的 `id`、`name`、`description`，单项 tooltip 展示名称与完整说明。
- 空位是 `occupied=false` 的留白：不显示棋子、职业/槽位编号、血条、死亡标记或 tooltip。真正阵亡的已占用格仍保留棋子、124px 居中短血条与死亡标记，避免将死亡误画为空位。
- 待出牌队列保持同实例互斥；不同实例仅在前一张的表现结束后进入真实 Controller。取消、失效 guard、根节点 `PROCESS_MODE_DISABLED` 暂停和终局路径均不产生额外出牌或 SP 消耗。
- 阵容编辑改为 Run 界面内部的 `Control` 浮层：居中完整显示地图，不挤压原布局；Esc 或“完成”关闭，右侧库存完整可见。每次调整后重新绑定库存与兵种显示。

### 本轮已验证

- `tests/pending_card_queue_contract_test.gd`：6 tests / 46 assertions 通过，覆盖不同第二张的顺序等待、取消、guard 失效、真实 Run 暂停、终局和重复实例。
- `tests/inkjade_relic_formation_ui_test.gd`：3 tests / 47 assertions 通过，覆盖默认 1/4/5/6 占位、精英空位与实际阵亡的区分、遗物 View Model/tooltip 和横向宽度约束。
- M4 专项：43 tests / 792 assertions / 0 failures，日志为 `.godot/test-logs/pending-availability.log`。验证赤焰 `burn01` 初始不可用，在 `markBurn` 提交后、表现 busy 期间 Controller 与 UI 同步可用，第二张可进入待出牌队列；真实 formation slot 拖拽也已通过。独立窗口截图为 `tests/artifacts/inkjade_relic_formation/01_real_run_four_piece_relics.png` 与 `02_real_run_elite_vacancies.png`。
- 真实阵容拖拽：`tests/capture_run_formation_drag.gd` 通过，日志 `.godot/test-logs/formation-modal-root.log` 记录 `FORMATION DRAG failures=0`；已目检 `tests/artifacts/formation/map-expanded.png` 与 `map-drag-expanded.png`，覆盖 slot 4→1 和库存旗兵→slot 4。
- M5 专项：`run_m5_06` 为 48 tests / 2952 assertions 通过。

最终常规回归、M4 E2E 与库存拖拽取证均已完成。Windows Portable Pack 已重打包，日志为 `four-piece-final-build.log`；从 `build/YizheCardGame/YizheCardGame.pck` 启动的 smoke 日志为 `build/YizheCardGame/logs/four-piece-final-smoke.log`，退出码 0，除机器根证书提示外未见脚本或资源错误。上述范围以外的既有脏改动不归入本轮。
