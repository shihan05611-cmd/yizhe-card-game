# M3_FINAL 独立 Review

## 结论

**Review mode：M3_FINAL**  
**结论：PASS**

无阻塞 findings。此结论仅表示完整 M3 的代码可行性门禁通过，可交由模块中枢进行规则、玩法与数值整合；不构成产品最终验收。

## Findings

无阻塞 findings。

- `CardCombatBridge` 是已安装玩家卡牌运行时的唯一效果事务入口：它先做权威卡/请求/validator/SP 预检，再支付 `actual_cost`，经现有 M2 `EffectRegistry` 执行一次效果，最后由 `HandRuntime` 提交去向、次数、事件和充能。没有卡牌层伤害或 Buff 重算。
- 预检拒绝发生在支付和效果调用前。效果或 post-success 已提交后失败会返回 `committed_failure`、保留提交前缀并停用队列；`BattleCardSession` 会继而停用会话，未发现伪回滚或自动重试路径。
- `PlayerEnergyCoordinator` 是安装 M3 运行时时所有玩家能量写入的统一阈值入口；`BattleRuntime` 的遗物、横幅和反击路径均委托 `apply_player_energy`。敌方保持 `EnemySkillAdapter` 的旧式 SP/能量/大招路径。
- `BattleDeckAssembler` 保留自由技多重列表、主动专属技、骑士被动排除和 roster 计数；`basicDamage` 在目录、装配、HandRuntime 以及桥请求权威边界均被拒绝，M1/M2 定义与敌方适配仍保留。
- `BattleCardSession` 负责首抽、显式结束回合时的先弃手、一次 M2 `resolve_round`、非终局新增抽 `2+N` 与终局停止。`RoundResolver.m3_obligations` 只保留兼容 trace，实际由会话写为 `fulfilled` 或 `skipped_terminal`，未发现双执行。
- 未发现 M4 场景/UI/动画或 M5 奖励、交易、招募状态机、存档实现。`docs/m3-handoff.md` 的接口、Q1-Q8、测试数字和排除项与当前实现/本次运行一致。

## 实际验证

使用 Godot `4.7.1.stable.official.a13da4feb`。

1. M3 聚焦（不加载完整共享 RNG golden；含 M3 相关 M2 PieceAttack、PieceReactions、EnemySkillAdapter 回归）：

   ```powershell
   & $godot --headless --path . --log-file .godot\test-logs\m3-final-review-focused-20260904.log --script res://tests/run_m3b.gd
   ```

   退出码 `0`；`71 tests / 937 assertions / 0 failures`。

2. 常规全量（包含 M2 RoundResolver、BattleRuntime、Damage golden 等回归；按用户要求不运行 1000 场稳定性）：

   ```powershell
   & $godot --headless --path . --log-file .godot\test-logs\m3-final-review-regular-20260904.log --script res://tests/run_regular_without_stability.gd
   ```

   退出码 `0`；`265 tests / 9720 assertions / 0 failures`；输出明确为 `OMITTED BY USER REQUEST: res://tests/m2_battle_stability_test.gd`。

两个日志均扫描 `SCRIPT ERROR|Parse Error|Invalid|Assertion failed|FAIL:`，无匹配。`git diff --check` 无输出。

## 范围审计

M3 生产变更位于允许的卡牌运行时、定义/目录、`HandManager`，以及任务书许可的 `BattleRuntime`、`RoundResolver`、`PieceAttack` 和 `PieceReactions` 最小接线；测试与交接文档也在许可范围。M3 聚焦 runner 只组装卡牌确定性/流隔离测试，没有再次加载完整 `rng_test.gd` golden。

工作树在本批开始前已带有大量 M1/M2 未跟踪文件和既有修改。`tests/run_all.gd`、`tools/run_headless_tests.ps1` 不属于 M3 默认文件范围，但现有 diff 是先前通用测试运行器/编译失败自测支持，未在本次 Review 改动；任务索引也已明确记录该脏基线。仅凭当前 `git status` 无法将它们归因于 M3，提交时仍应按任务归属拆分。

## 未覆盖或环境限制

- 未运行 `m2_battle_stability_test.gd` 的 1000 场稳定性回归，是用户明确的测试决议；属于未验证，不是失败。
- M3 聚焦 runner 有意不重复完整共享 RNG golden；常规回归仍加载 `rng_test.gd`。聚焦已验证本模块所需的同 seed 牌序与 deck/combat/enemyPolicy 隔离。
- Godot 启动输出 Windows 根证书读取失败和 `user://.godot/test-logs` 建目录提示；两次运行仍以退出码 0 完成并写入项目日志，且无产品脚本/解析/断言失败。

## 门禁交接

M3_FINAL 代码可行性门禁通过。模块中枢可据此整合 M3 规则验收；M4 是否启动仍由中枢依冻结接口与产品决策处理。
