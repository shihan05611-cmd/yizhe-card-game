# M5-06 神通休眠迁移与完整通关

状态：已完成（Executor 证据完成，等待 M5-90 独立 Review）

建议：`gpt-5.6-terra` / `high`

Allowlist：`systems/roguelike/` 的独立休眠模块、M5 相关 `tests/` 与测试入口、`docs/parity-checklist.md`、`docs/m5-handoff.md` 及 M5 阶段证据文档。

## 目标

迁移三种神通及两件进化遗物的领域代码和独立测试，但保持不可从当前游戏流程访问；同时完成不使用神通的三章无头通关测试和 M5 交接材料。

## 允许范围

- `systems/roguelike/` 下新增独立神通领域模块及适配端口。
- 为 `charge`、`assault`、`sacrifice` 和两件进化遗物新增直接单元测试。
- 新增 M5 完整通关测试入口。
- 更新 `docs/parity-checklist.md` 并新增 `docs/m5-handoff.md`。

## 禁止范围

- 不从 Run 系统、GameRoot、BattleController、M4 UI 或输入映射调用神通模块。
- 不把两件神通进化遗物放入奖励、商店、锻造或通关测试。
- 不新增玩家可见神通按钮、选择页或调试入口。
- 不做 M6 批量模拟、胜率统计、平衡调整或 1000 次回归。

## 依赖

- M5-01 至 M5-05 全部完成。
- M2 战斗端口和 M3 卡牌规则，仅供休眠模块适配与测试替身使用。

## 完成条件

- 三种神通的限制、次数、原子回滚和效果代码完成迁移，并能通过独立测试直接调用。
- `shentongAssaultBurst` 与 `shentongChargeOverload` 的增幅查询和神通组合测试通过。
- 代码搜索和集成测试证明当前玩家流程不存在神通调用入口。
- 固定种子无头流程能从开局推进至第三章 Boss 胜利，覆盖地图、普通遗物、经济、招募和战斗提交，且不使用神通。
- `m5-handoff.md` 明确记录休眠模块未来接线点、当前禁用边界和后续风险。
- M5 聚焦测试与常规非稳定性测试通过并回报证据。

## 2026-09-08 执行证据

- 休眠领域边界：`systems/roguelike/dormant_shentong_domain.gd` 与
  `dormant_shentong_battle_port.gd` 独立存在，生产组合根不 preload、不实例化。
- 独立合约覆盖：`charge`、`assault`、`sacrifice` 的使用条件、独立次数、效果、
  `shentongAssaultBurst` / `shentongChargeOverload` 查询，以及世界状态、次数、结算和
  RNG replay 的原子回滚。
- 三章 E2E：固定 seed `m5-06-three-chapter-no-shentong` 从初始弈者选择出发，沿权威
  3×10 地图逐章推进，共完成 30 个节点和三场 Boss；每个战斗节点由真实
  `RoguelikeBattleAdapter` 打开 `RunBattleProgress` 并提交胜利，不使用神通。路径同时
  获得普通遗物、完成商店购买，并完成第一章两次招募。
- 未接线证明：自动测试扫描 Run contract/lifecycle/progress、`GameRoot`、
  `BattleController`、`project.godot` 和 `ui/`，禁止休眠模块 preload、类名、handler
  或 `use_shentong` 调用；同时断言 InputMap 不含神通 action。独立 `rg` 搜索只命中
  两个休眠模块自身。
- 聚焦命令（所有 Godot 命令均把日志写入工作区）：
  `Godot_v4.7.1-stable_win64_console.exe --headless --path <project> --log-file <workspace-log> --script res://tests/run_m5_06.gd`
  → 累计 M5 阶段 `tests=46 assertions=2711 failures=0`，退出码 0；其中 M5-06
  新增的休眠神通与三章 E2E 为 `tests=7 assertions=711 failures=0`。
- 常规非稳定性命令：
  `... --script res://tests/run_regular_without_stability.gd`
  → `tests=369 assertions=13666 failures=0`，退出码 0；按约定省略 M2 1000 次稳定性与
  单独的图形 E2E。
- Editor parse/import：`--headless --editor --quit` 退出码 0，无脚本解析/导入错误。
  当前设备仍会报告 Windows 根证书读取和沙箱内 AppData editor settings 写入告警，
  不影响上述测试与退出码。
