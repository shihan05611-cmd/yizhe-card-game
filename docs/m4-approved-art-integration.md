# M4 已认可美术接入（2026-09-05）

本次由主助手亲自实现，按用户指示不安排独立 Review。本文记录当前接入，取代旧交接文档里的美术约束；不改变 M4 以外阶段状态。

## 接入结果

- 主入口仍为 `res://scenes/main.tscn`。中央共享青玉棋盘，双方各两列三行，弈者在外侧；底部暖纸手牌，左侧 SP/抽牌，右侧结束回合/弃牌/消耗，上方回合与控制项。
- 1–3 个弈者按侧栏高度均分；手牌有独立空间，最多七张，保留悬停、拖动、出牌和不可用原因。
- 四兵种读取真实 VM 的 `class_id`：`shield` 甲卒、`crossbow` 机弩、`assassin` 刺客、`banner` 旗兵。显示“刺客”不改数据目录中的“死士”。
- 图像来自用户认可的 V4 Canvas 路径。无脸、侧视、单根袍柱、敌我相向；保留八套敌我 SVG 图集，每套九个出手姿态。攻击表现由现有事件触发，时间使用队列传来的时长。
- `tools/art/approved-piece-v4.html` 是原始绘制来源；在项目目录执行 `node tools/art/build-pieces.mjs` 可重新生成 `ui/art/pieces`。Godot 负责导入 SVG，运行时用 AtlasTexture 切换动作帧，无需重新画图。
- 日志抽屉覆盖显示，不挤压或移动棋盘。所有战斗命令、事件、锁定、倍速和重开接口继续复用。

## 必须区分的现有初始化缺口

`app/battle_bootstrap.gd` 的 `_team()` 目前固定使用 `piece_classes["default"]`，并以原调参表构造双方数值。因此真实开局还是普通棋子；本次如实显示为“棋子”，没有在视图里伪造甲卒、机弩的身份或被动。

四兵种图形映射和动作已在实际 Godot 场景中覆盖验证，但让真实初始阵容产生这些兵种，需要战斗初始化模块后续配置。该工作会涉及身份、属性和被动，按用户“战斗逻辑不要碰”明确留在本次范围之外。

未提供立绘的敌方弈者保留姓名与能量，不冒用其他角色的立绘。

## 验证与证据

- 常规非稳定性回归：323 tests / 10947 assertions / 0 failures。
- 单独 M4 E2E：5 tests / 1655 assertions / 0 failures。相同种子 1×/4× 都提交 46 条命令、得到相同的 759 条事件序列，表现时长比为 4.000。
- 没有运行 1000 场稳定性回归。
- 实际窗口运行 `tests/capture_approved_m4.gd`：1200×700、1280×720、1600×900；零/七手牌、悬停拖动、日志、死亡、终局、三弈者。另用真实主场景完成一次拖牌与一次结束回合，各只提交一条命令，并回到下一回合。
- `tests/artifacts/approved_m4/01`–`09` 是 Godot 展示状态截图（其中 `03_hand_7.png` 覆盖四兵种）。`10_actual_game.png`–`13_actual_next_round.png` 是真实开局、出牌、战斗播放与下一回合截图。不要把前九张当作已改动初始阵容的证据。
- `core`、`systems`、`autoload`、`app`、`data` 共 155 个基线文件 SHA256 全部相同。基线保存在 `.godot/m4-approved-baseline/logic-hashes.json`，原表现代码备份为同目录 `presentation.zip`。仓库此前已有未提交变更，本次未提交或重置它们。
- 环境仍打印系统证书存储/着色器缓存写入警告；最终运行及测试日志没有脚本解析错误、缺失节点或测试失败。真实 OpenGL 窗口已成功渲染与截图。

复现命令（本机 Godot）：

```powershell
& '.godot/m4-engine/Godot_v4.7.1-stable_win64_console.exe' --path . --log-file '.godot/m4-live.log'
& '.godot/m4-engine/Godot_v4.7.1-stable_win64_console.exe' --path . --log-file '.godot/m4-capture.log' --script res://tests/capture_approved_m4.gd
& '.godot/m4-engine/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file '.godot/m4-regular.log' --script res://tests/run_regular_without_stability.gd
& '.godot/m4-engine/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file '.godot/m4-e2e.log' --script res://tests/run_m4_e2e.gd
```
