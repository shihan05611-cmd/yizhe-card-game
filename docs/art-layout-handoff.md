# 战斗界面第一期布局升级交接（历史快照）

> ART_LAYOUT_FINAL 已通过；本文件只保留本轮布局升级的证据，不能作为当前项目待办。当前状态见 [`迁移现状与后续路线-2026-09-08.md`](迁移现状与后续路线-2026-09-08.md)。

## 状态

- ART-1～ART-4 已完成实现与整合验证，等待独立 `ART_LAYOUT_FINAL` Review。
- 本文只记录实现、证据和后续可调参数，不替代用户的最终美术验收。
- 战斗规则、Controller、ViewModel、表现事件合同、队列时钟和忙锁语义未因本轮布局升级改变。

## 已接受并落地

- BattleScreen 使用外边距、顶栏和叠层主区组成的容器骨架；手牌层不参与主区纵向高度分配。
- 我方和敌方使用镜像列，弈者面板贴在各自棋盘上方并按人数同步高度。
- 日志默认隐藏并退出 MainRow；Tab、L 和 HUD 按钮进入同一切换函数。抽屉宽 300，0.18 秒从右侧非阻塞滑入/滑出。
- 日志关闭期间累计未读数字，最高显示 `99+`；打开清零，列表保持顺序并自动滚底，终局不强制打开。
- 手牌无固定底框；0 张牌时不出现空框。7 张牌使用 150×210 卡面、最小安全可见间距和必要的整体缩放。
- 正常牌序保持右侧后牌覆盖前牌右缘；hover/drag 单独置顶，不重排邻牌。
- 棋子职业名本地化，空 Buff 行隐藏，HP 数字叠在血条上；阵亡态由灰化、划线节点共同表达。
- HUD 分为回合/SP、四牌堆短标签、倍速/自动/日志/结束回合三组；结束回合保留唯一高对比主操作。
- 结果和 fatal 使用居中卡片、文字原因和可见主按钮。
- 正式动态可见对象继续由 `.tscn` / `PackedScene.instantiate()` 创建；没有加入 `_draw`、`draw_*` 或脚本拼装 Control 树。

## 运行时视觉证据

目录：`tests/artifacts/art1/`

- `01_default_log_hidden.png`：1200×700，默认日志隐藏。
- `02_log_opened.png`：1200×700，日志打开。
- `03_hand_7.png`：1200×700，7 张手牌。
- `04_hand_0.png`：1200×700，0 张手牌且无底框。
- `05_hover_drag.png`：1200×700，同时展示 hover 与 drag 置顶状态。
- `06_result.png`：1200×700，胜利结果卡片。
- `07_1600x900.png`：1600×900 响应式布局。
- `08_1280x720.png`：1280×720 响应式布局。

ART-4 阻塞级目检只检查资源缺失、不可读、明显遮挡/溢出和错误状态；八图未发现上述阻塞项。色彩、字体和像素级间距未在本轮裁决。

## 验证结果

- ART 聚焦：`16 tests / 466 assertions / 0 failures`。
- M4 聚焦：`44 tests / 2298 assertions / 0 failures`；自动战斗 1x/4x 表现时间比例为 `4.000`。
- ART 图形 smoke：`2 tests / 36 assertions / 0 failures`，已包含在 ART 聚焦。
- M4 图形 smoke：`1 test / 18 assertions / 0 failures`，已包含在 M4 聚焦。
- 常规非稳定性回归：`322 tests / 10936 assertions / 0 failures`。
- 按用户要求未运行 1000 场稳定性回归。

## 后续可调美术参数

这些参数可在整块验收后由用户继续调节，不应改变战斗逻辑：

- `scenes/battle/battle_screen.tscn`：根边距 16、主区间距 12、底部渐隐高度 200。
- `ui/battle/battle_screen.gd`：日志宽 300、开合时间 0.18 秒。
- `scenes/cards/card_view.tscn`：卡面 150×210 及卡内文字/标签偏移。
- `ui/cards/hand_view.gd`：首选间距 116、最小可见比例 0.72、最大旋转 7°、弧高 24、底边距 20。
- `ui/cards/card_view.gd`：hover 缩放 1.08、上移 28。
- 各战斗 `.tscn` 内联 StyleBox 的颜色、描边、圆角和字号属于第二期统一 Theme 的候选项。

## 明确保留到第二期

- 共享 `battle_theme.tres`、面板层级和全局字阶收敛。
- 全屏冷暖色重定与 FX 强度调整。
- 敌方弈者正式立绘补齐、双方立绘统一裁切框和安全区。
- 用户基于整块运行效果进行的像素级间距、字体和颜色微调。

## 复现命令

在 Godot 项目根目录执行：

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --script 'res://tests/capture_art_layout_evidence.gd'
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --script 'res://tests/run_art_layout.gd'
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --script 'res://tests/run_m4.gd'
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --script 'res://tests/run_regular_without_stability.gd'
```
