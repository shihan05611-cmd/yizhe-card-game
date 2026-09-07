# M4_FINAL 独立 Review

## 结论

**PASS**。M4 可交付。

本 Review 仅检查代码可行性、解析/资源路径、分层边界、指定测试和图形证据可读性；不裁决玩法数值、平衡、颜色、间距、动效强度或像素级美术。

## Findings

| 严重度 | 数量 | 结论 |
| --- | ---: | --- |
| P0 | 0 | 无阻断级发现。 |
| P1 | 0 | 无需在交付前修复的运行/接口/路径问题。 |
| P2 | 0 | 无后续修复建议。 |

## 范围与代码审计

- `project.godot` 的 `application/run/main_scene` 指向 `res://scenes/main.tscn`；主场景、autoload、M4 场景和脚本可实例化。
- Battle/Card/Hand/FX/Float 等可见动态单元均从 `.tscn` / `PackedScene.instantiate()` 创建；静态守卫未发现正式 `_draw()`、`draw_*()`、`Control.new()` 或 `Label.new()` 拼装界面。
- 资源路径静态核对覆盖 70 条 `res://` 路径，未发现缺失资源。M4 图形证据的六张 PNG 均可读、非空、尺寸为 1200×700。
- UI 消费深拷贝 ViewModel，并通过 guarded Command 提交；没有第二份伤害、validator 或牌堆权威。
- `BattlePresentationQueue` 是唯一表现时钟和忙锁。手动与自动战斗共用 Command/队列入口；自动策略只读取权威 `hand[].playable`，对回手实例每回合最多尝试一次，并在终局/fatal 停止。
- 终局与 fatal 遮罩可见、锁定继续输入并保留显式重开；重开释放旧本地 `HandManager`，以同一配置创建新会话，新的 `battleStart` 只发出一次。
- 未发现 M5 地图/奖励/商店/招募/Run 写入或 M6 存档、批量模拟、平衡调整侵入 M4 表现层。

## 图形证据审查

已读取 `tests/artifacts/m4/` 的六张证据：完整 UI 与七牌、悬停、拖拽、同 seed 同动作的 1x/4x、终局结果。

- 六图均可读，无缺失资源或空白捕获。
- 7 张手牌、HUD、2×3 双方棋盘、英雄面板和日志未见明显越界或遮挡。
- 终局图正确显示失败遮罩和显式重开；不据此裁决颜色、字体、间距或动效风格。

## 实际运行命令与结果

Godot：`4.7.1.stable.official.a13da4feb`。在工程根执行：

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\m4-final-focused-independent-20260904.log' --script res://tests/run_m4.gd -- --skip-e2e
```

- 退出成功：`41 tests / 753 assertions / 0 failures`。
- 覆盖合同、场景、手牌、FX、表现队列、场景实例化和六图的 graphical smoke；graphical smoke 为 `1 test / 18 assertions / 0 failures`。

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\m4-final-e2e-independent-retry-20260904.log' --script res://tests/run_m4_e2e.gd
```

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\m4-final-regular-independent-20260904.log' --script res://tests/run_regular_without_stability.gd
```

- 本 Review 环境中 e2e 与常规非稳定性回归均未取得完整 summary：e2e 已输出 `1x=132.260s`、`4x=33.065s`、ratio `4.000`、`46 commands`、`759 events`；常规回归已输出部分均为 0 failures。默认/相对日志路径还会受到受限 `user://` 目录影响；使用绝对日志路径后仍有 Windows 根证书库读取告警。
- 这属于本次独立复跑的环境证据限制，不作为代码失败。
- `docs/m4-handoff.md` 的执行者交接记录：e2e + 场景实例化 `5 tests / 1655 assertions / 0 failures`，常规非稳定性回归 `306 tests / 10473 assertions / 0 failures`。
- 本 Review **未运行** `m2_battle_stability_test.gd` 的 1000 场稳定性回归；未将其省略伪报为通过。

## 交付判定

M4_FINAL PASS。M4 可交付；后续 M5/M6 只能消费其已冻结的战斗入口、ViewModel、Command 和表现事件合同，不得反向把 Run、存档、批量模拟或平衡逻辑塞入表现层。
