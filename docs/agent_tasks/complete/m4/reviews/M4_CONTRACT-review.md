# M4_CONTRACT 独立 Review

## 结论

**PASS**。允许启动 M4-2、M4-3、M4-4。

本 Review 仅检查解析/运行可行性、接口与分层边界、合同和指定测试；未裁决玩法数值、美术或平衡，未修改实现、测试或任务书。

## 范围审计

- 生产 bootstrap 通过真实 `ContentCatalog`、`BattleRuntime`、`BattleCardSession` 和 `HandManager` 建立会话；`app/` 不引用测试 fixture。
- `BattleController` 只向场景消费者提供深拷贝 ViewModel 和 `play_card(instance_id)`、`end_player_turn()`、表现倍速、自动战斗开关等 Command 形状；会话存在时 `HandManager` 的原始牌堆 mutation 入口拒绝执行。
- `inspect_card` 复用 `BattleRuntime.inspect_player_card` / `CardCombatBridge.inspect_playability` 的同一权威预检；聚焦测试覆盖查询不移动卡牌、不扣 SP、不写成功次数、不消费 combat/enemy RNG、不产生表现事件。
- `battleStart` 由 `BattleController.start` 的生产组合根单点触发；committed failure 进入可见 fatal ViewModel 状态，后续 Command 被拒绝，不自动重试。
- 表现事件采用 JSON-safe 深拷贝 envelope：`sequence`、`batch_id`、`event_id`、`source`、`visual_target`、`payload`；W-021 至 W-024 的棋子/单位与阵营 Buff/批次/遗物来源均有合同测试。
- 未发现提前创建正式战斗场景、卡牌 UI、特效播放器，或引入 M5/M6 Run、存档、批量模拟范围。

## Findings

### P0 / P1

无。

### P2（已修补）

- W-037 曾仅以满血 `1.0` 覆盖队伍生命百分比，无法直接证明非满血时按全体当前 HP / 全体最大 HP 聚合。补丁已增加该断言，并更新对应证据；修补后 M4 合同测试为 `9 tests / 146 assertions / 0 failures`。该问题不阻塞本合同门禁。

## 实际运行命令与结果

在工程根执行，Godot 为 `4.7.1.stable.official.a13da4feb`：

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\m4-contract-independent-20260904.log' --script res://tests/run_m4_contract.gd
```

- Review 初次聚焦运行：`9 tests / 145 assertions / 0 failures`。
- W-037 补丁后的执行回报：`9 tests / 146 assertions / 0 failures`。

```powershell
& 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --log-file 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版\.godot\test-logs\m4-contract-regular-independent-20260904-3.log' --script res://tests/run_regular_without_stability.gd
```

- 常规非稳定性 runner 在本 Review 环境未得到完整汇总：默认/相对日志路径会因受限的 `user://logs` 或 `user://.godot/test-logs` 报错，使用绝对日志路径后已执行部分均为 0 failures，但进程未产生最终 summary。还同时出现 Windows 根证书库读取告警。
- 以上属于环境/证据限制，不作为项目代码失败；本 Review 未运行 `m2_battle_stability_test.gd` 的 1000 场回归。

## 放行

M4_CONTRACT PASS；M4-2、M4-3、M4-4 可并行启动。M4_FINAL 前应保留 W-037 的非满血聚合断言和常规非稳定性回归的完整可复现输出。
