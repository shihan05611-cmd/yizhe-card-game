# M4 战斗表现交接（历史快照）

> M4_FINAL 已通过；本文件保留当时的实现与证据。当前项目状态请以 [`迁移现状与后续路线-2026-09-08.md`](迁移现状与后续路线-2026-09-08.md) 和 [`m5-handoff.md`](m5-handoff.md) 为准。

## 状态与边界

- 状态：M4-6 实现与执行者证据已完成，等待 `M4_FINAL` 独立 Review；本文不构成最终验收。
- 入口：`project.godot` 的 `application/run/main_scene` 指向 `res://scenes/main.tscn`，启动即进入正式演示战斗。
- 范围：战斗场景、2×3 双方棋盘、HUD/日志、手牌、技能 FX、表现队列、1x–4x、自动战斗、终局/fatal 与显式重开。
- 未进入 M5/M6：没有地图、奖励、商店、招募、Run 写入、存档或平衡调整。
- 按用户要求未运行 `m2_battle_stability_test.gd` 的 1000 场回归。

## 冻结接线

- `BattleSceneCoordinator.set_auto_battle(enabled)` 只读取 Controller 的权威 `hand[].playable`，串行调用与手动输入相同的 `submit_play_card` / `submit_end_turn`。
- 同回合每个回手实例最多自动尝试一次；卡牌拒绝后看下一张权威可用牌，无牌则结束回合；结束回合若被拒绝则停止自动，避免重试环。
- `BattlePresentationQueue` 是唯一表现时钟与忙锁；逻辑先结算一次，再按稳定 sequence 播放，倍速不进入规则层。
- `BattleSceneCoordinator.restart_battle()` 清空队列/FX/临时反馈，释放旧本地 HandManager，再用同一配置创建新 Controller；新战斗只产生一次 `battleStart`。
- 胜负或 fatal 会停止自动。结果层/fatal 层保留可见原因和显式重开按钮。
- 正式动态卡牌、英雄条目、日志条目、飘字、标记与 FX 均使用 `.tscn` / `PackedScene.instantiate()`；表现脚本无即时绘制替代。

## 自动证据

- M4-6 e2e + 场景实例化：`tests/run_m4_e2e.gd`，5 tests / 1655 assertions / 0 failures。
  - 完整同 seed 1x/4x：46 个逻辑命令、759 个稳定表现事件、最大逻辑调用深度 1。
  - 虚拟表现时长：1x `132.260s`，4x `33.065s`，比值 `4.000`；最终逻辑 VM 与事件数组一致。
  - 影狩回手牌以两命令有界探针证明“尝试一次后结束回合”，无同卡死循环。
  - 终局结果层显式重开后 round=1、result=null，新 Controller 的 `battleStart` 恰好一次。
- M4 聚焦增量（长 e2e 已在上一命令单独完成）：`tests/run_m4.gd -- --skip-e2e`，41 tests / 753 assertions / 0 failures。
- 图形 smoke：包含在上述聚焦命令，1 test / 18 assertions / 0 failures；六张 PNG 均可读、非空且为 1200×700。
- 常规非稳定性回归：`tests/run_regular_without_stability.gd`，306 tests / 10473 assertions / 0 failures；明确单独运行 focused e2e，并省略 1000 场稳定性套件。
- Godot 控制台仅出现 Windows 根证书读取警告；图形捕获另有 GLES3 shader cache 写入警告。测试、截图保存与进程退出码均成功，未进入应用 fatal。

## 1200×700 图形证据

证据目录：`tests/artifacts/m4/`

- `01_battle_ui_7_cards.png`：完整 HUD、双方 2×3 棋盘、双方弈者、日志与七张手牌。
- `02_card_hover.png`：悬停放大与提升层级。
- `03_card_drag.png`：拖拽越过出牌方向的中间状态。
- `04_same_action_1x.png`：seed `m4-visual-same-action` 的首张权威可用牌，1x。
- `05_same_action_4x.png`：相同 seed、相同卡实例与动作，4x。
- `06_battle_result.png`：正式自动战斗抵达 lose 终局，输入锁定且显示显式重开。

执行者只按缺失资源、不可读、明显遮挡/溢出和错误状态检查。首次捕获发现旋转外侧手牌越过窗口下沿，已修正 HandView 对实际父容器的布局钳制与纵向基线，并以旋转后四角断言和重采图确认；没有继续做像素级风格精修。

## 未决项与后续边界

- 最终颜色、间距、字体层级、动画手感和 FX 强度留给用户整块调整，不作为本草稿的自验收结论。
- 默认演示 seed 可稳定完成战斗，但胜负本身不是 M4 数值验收；M6 才负责批量模拟与平衡调参。
- `M4_FINAL` 应独立检查解析/运行风险、入口/资源路径、分层边界和上述命令可运行性；不要重复玩法平衡裁决。
- M5 只能消费本交接的战斗入口/结果，不得让地图或 Run UI 直接修改 BattleState/牌区。
- M6 可在既有 Command/VM/事件合同之上加存档、批量模拟和数值工具，不得将其反向塞入表现脚本。
