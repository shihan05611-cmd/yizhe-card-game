# ART_LAYOUT_FINAL 独立 Review

## 结论

**PASS**。本期布局升级可交由用户进行第二期前的整体美术调节。

本 Review 仅检查解析/明显运行风险、接口与路径、分层边界、指定测试和阻塞级视觉状态；不裁决 P2 色板、字体、立绘、FX 或像素级细节。

## Findings

| 严重度 | 数量 | 结论 |
| --- | ---: | --- |
| P0 | 0 | 无阻断级发现。 |
| P1 | 0 | 无需在交付前修复的运行、接口或路径问题。 |
| P2 | 0 | 本 Review 无新增后续修复建议；任务书保留的 Theme、色板、字体、立绘和 FX 均未提前裁决。 |

## 范围、合同与节点边界

- ART 实现集中于 `ui/`、`scenes/` 与 `project.godot` 的 `toggle_combat_log` InputMap。Controller、ViewModel、表现事件合同与 `BattlePresentationQueue` 未被布局层改写；界面继续消费深拷贝 VM 并发出既有 Command 信号。
- 根场景以 `MarginContainer → VBoxContainer → MainStack` 重排，`HandLayer` 叠在 `MainStack` 内、不参与 VBox 高度分配；日志关闭时 `LogSlot.visible = false`，不占 MainRow 宽度。
- Tab、L 和 HUD 日志按钮汇入同一开合入口；未读角标、自动滚底、终局/fatal 不强开日志均有实现与测试覆盖。开合 Tween 不接入队列忙锁。
- 0/1/7 手牌、旋转边界、hover/drag 不重排邻牌、结果/fatal 卡片和快捷键入口均由 ART 聚焦测试覆盖。
- 可见动态对象继续从 `.tscn` / `PackedScene.instantiate()` 创建。静态扫描未发现 ART 生产层新增 `_draw()`、`draw_*()`、`Control.new()` 或 `Label.new()` 拼装界面。
- 对 `scenes/` 与 `ui/` 的 53 条 `res://` 资源路径做了静态核对，缺失为 0。

## 图形证据审查

已读取 `tests/artifacts/art1/` 的八张 PNG：默认日志隐藏、日志打开、7 手牌、0 手牌、hover/drag、结果、1600×900、1280×720。

- 八图全部可读、非空，文件状态与名称相符。
- 未见资源缺失、阻断级遮挡/溢出或错误状态。
- 0 手牌图无固定底框；7 手牌、HUD、双方棋盘和终局卡片在三档尺寸中未见明显越界。
- 此结论不延伸至颜色、字体、立绘裁切、间距手感、动效强度或像素级美术裁决。

## 实际运行命令与结果

Godot：`4.7.1.stable.official.a13da4feb`。在工程根执行：

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\art-layout-final-independent-20260904.log' --script res://tests/run_art_layout.gd
```

- 退出成功：`16 tests / 466 assertions / 0 failures`。
- ART 图形 smoke 已包含其中：`2 tests / 36 assertions / 0 failures`。

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\art-layout-final-m4-focused-independent-20260904.log' --script res://tests/run_m4.gd -- --skip-e2e
```

- 退出成功：`41 tests / 749 assertions / 0 failures`；M4 表现队列测速为 `1x=0.580s`、`4x=0.145s`、比例 `4.000`。

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\art-layout-final-regular-independent-20260904.log' --script res://tests/run_regular_without_stability.gd
```

- 常规非稳定性回归在本 Review 环境未返回完整 summary。日志中 ART 和已执行的 M3/M4 组均为 `0 failures`；Windows 根证书库读取告警不构成代码失败。
- 该项是本次独立复跑的环境证据限制。`docs/art-layout-handoff.md` 的完整执行记录为 `322 tests / 10936 assertions / 0 failures`。
- 本 Review **未运行** 1000 场 `m2_battle_stability_test.gd`，未将其省略伪报为通过。

## 交付判定

ART_LAYOUT_FINAL PASS。第一期布局改造在既定 M4 合同与表现边界内完成，可交给用户做后续整体美术调节；第二期的共享 Theme、字阶、色调、立绘补齐和 FX 强度应继续保持为独立工作，不应侵入战斗权威、事件合同或队列时钟。
