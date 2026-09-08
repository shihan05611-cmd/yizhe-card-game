# M5 clean-state 独立复审

- 身份：Review Agent
- 日期：2026-09-08
- 对象：当前完整工作树中的 M5-01～M5-06 最终状态
- 性质：只读复审；实现、测试、旧报告均未修改

## 当前态范围

本轮从当前工作树重新检查 Run 闭合契约和事务 RNG、三章 `3×10` 地图与遭遇、生命周期和招募部署、奖励/商店/锻造/事件经济、权威选项快照及原子回滚、免费技能多重集、普通/职业遗物、Run→Battle 桥、胜败和跨战进度提交、三章固定种子 E2E，以及三种神通和两件进化遗物的“已迁移但完全休眠”边界。

用户冻结的 M5 Run 六槽基准为 `shield, shield, shield, assassin, crossbow, banner`。这项规则有意覆盖旧 Web/M1 的 `[shield×3, crossbow×3]`，因此不按旧 parity 判错；检查重点是它只作用于 Run 战斗且不外溢修改 M1 或 M4 direct 路径。

本轮不审 M6、正式 Run UI、数值平衡、胜率或 1000 次稳定性。

## 明确排除的一次性过程问题

以下均不作为当前态缺陷：首次未导入时的 `class_name` 缓存缺失、首次资源扫描、曾遗漏 `--log-file` 引发的 `user://` 写入/崩溃、已经被最终累计 runner 替换的测试草稿、执行者静默或调度耗时，以及已经清理的旧报告坏串。当前 `.godot` 已导入，本轮每条 Godot 命令均显式写入工程内 `.godot/test-logs/`。

## 独立检查结果

- Run contract 保持 JSON-safe 闭合字段；普通遗物 ID 唯一，免费技能 ID 明确允许重复。事务 RNG 在失败时把已抽值按顺序放回 replay 队列，拒绝嵌套事务与异步返回，生命周期命令同时回滚 Run、选项 authority、battle authority 和 RNG。
- 地图/遭遇的三章节点、相邻行连边、前沿、固定/权重类型、普通/精英/Boss 预算和六槽 encounter 展开由 Web golden 覆盖；当前 fixture 行为数据未随来源路径/哈希 provenance 刷新而漂移。
- 经济选项有独立私有 authority；伪造字段、陈旧 ID、重复购买/领奖、余额不足及奖励货币溢出均在无状态或 RNG 改变下拒绝。免费技能奖励/商店保留多重集语义；`tradePermit` 每次出售只移除一个副本；奖励治疗不复活，锻造恢复会复活并补满六槽，且首次免费、后续递增并受折扣。
- 普通遗物与职业升级遗物的候选池、已拥有过滤和 Run battle ownership 注入均闭合；两件 `shentongEvolve` 遗物在奖励、商店和战斗投影中被双重过滤。`RoguelikeRelicActionAdapter` 提供 RelicSystem 所需的 11 类外部 action（追击、队伍攻击、Buff 查询、全体/单体遗物伤害、灼烧扩散、治疗、SP、施加灼烧等），BattleRuntime 继续组合两类英雄能量 action；Controller 保留 adapter 强引用，运行期 action 对象生命周期完整。
- Run 战斗按冻结六槽职业建立基础 HP/ATK/block/crit，再叠加永久成长、普通遗物和槽位 HP 比例；`shieldPlus` 的真实格挡后恢复与 `crossbowPlus` 仅作用槽 5 的 -20 最大生命/+10% 追击均有真实战斗图断言。M4 direct 配置仍走 `default×6`，常规 M2～M4 回归未受影响。
- `RunBattleProgress` 使用一次性 progress 对象隔离战斗草稿；胜利提交六槽 HP 比例和永久成长，失败丢弃本场草稿；伪造、陈旧、重复 settlement 不提交。真实 adapter/controller 被固定种子 E2E 用于经过的战斗节点，三章共推进 30 个节点并完成 3 场 Boss，同时覆盖普通遗物、一次商店购买和第一章两次招募。
- `charge`、`assault`、`sacrifice` 的次数、条件、效果、两件进化遗物查询、结算与 RNG/领域/战斗三方回滚有独立测试；生产 Run、GameRoot、BattleController、UI 和 InputMap 不 preload、不实例化、无调用入口。静态搜索仅在生产过滤常量中发现两件进化遗物 ID，没有发现休眠模块接线。

## 实际命令与数字

### Editor parse/import

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\m5-clean-rereview-editor.log' --editor --quit
```

- 退出码 0；项目扫描、全局类与 autoload 初始化完成，无脚本 Parse Error。
- 唯一控制台错误是 Windows 根证书读取失败，未影响退出码或项目解析。

### 累计 M5 focused

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\m5-clean-rereview-focused.log' --script res://tests/run_m5_06.gd
```

- 退出码 0：`tests=46 assertions=2730 failures=0`。

### 常规非稳定性回归

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\m5-clean-rereview-regular.log' --script res://tests/run_regular_without_stability.gd
```

- 退出码 0：`tests=369 assertions=13685 failures=0`。
- `ARCHITECTURE REAL violations=0`、`SAFE_FIXTURE violations=0`；负向 fixture/scan failure 计数是测试预期。
- runner 明确省略 `res://tests/m2_battle_stability_test.gd`，符合本轮禁止 1000 次稳定性的边界。

### Diff 与静态边界

```powershell
git diff --check
rg -n "DormantShentong|dormant_shentong|use_shentong" app autoload core systems ui project.godot --glob '!systems/roguelike/dormant_shentong_*.gd'
rg -n "shentongAssaultBurst|shentongChargeOverload" app autoload core systems ui project.godot --glob '!systems/roguelike/dormant_shentong_*.gd'
```

- `git diff --check`：退出码 0，无 whitespace error。
- 第一条休眠接线搜索无命中；第二条只命中 `battle_bootstrap.gd` 与 `run_lifecycle.gd` 的过滤 ID。

## 发现项

没有当前态阻断项。

唯一明确偏离是用户批准的 Run 六槽职业阵容；实现限定在 Run 专用 `_run_allies()`，M1 目录和 M4 direct `default×6` 未被修改，故不是缺陷。

## 旧报告对照

在完成上述第一轮独立代码检查和命令验证后，才读取旧 `M5-90-review.md`。旧报告曾记录并复验六槽职业投影缺口；当前实现、聚焦断言和 handoff 已包含修复。对照未发现旧报告遗漏且在当前状态仍成立的阻断项，也没有将旧报告中的一次性环境/过程噪声带入本结论。

## 最终结论

**PASS**
