# M3A_GATE 独立 Review

## 结论

**Review mode：M3A_GATE**  
**结论：PASS**

无阻塞 findings。此结论只表示 M3a 的代码可行性门禁通过，可进入 M3b；不构成玩法、数值或 M3 最终验收。

## Findings

无阻塞 findings。

审查到的实现边界如下：

- `CardDefinition` 与 `CardInstance` 分离；运行时实例以递增、可追踪的 `card-%08d` ID 区分，同一 `source_skill_id` 的副本不共用身份。
- `CardCatalog` 从 M1 的 skill/hero ability catalog 派生卡牌定义。`basicDamage` 仅在卡牌目录、牌库构造和 HandRuntime 输入边界排除；底层 M1/M2 的技能定义与 handler 未删除。
- `HandRuntime` 为 `RefCounted` 纯运行时，四区迁移集中在其 API；`HandManager` 仅持有和转发该运行时。抽牌、满手、弃牌重洗、结束回合、消耗/回手优先级、实例守恒、队列忙与 validator/executor 失败路径均有直接测试。
- deck 使用命名 `deck` RNG 流；测试确认 deck 与 combat/enemyPolicy 互不消费。队列重入被拒绝且外层执行失败不提交牌堆或成功次数。
- 未发现玩家 SP 支付、能量/充能、大招生成、`CardCombatBridge`、战斗回合接线、UI/场景或 M5 持久化实现。卡牌静态 schema 中保留的 `base_sp_cost` 和 ultimate 定义仅为后续桥接所需的静态元数据，未形成付款或大招事务。

## 实际验证

使用 Godot `4.7.1.stable.official.a13da4feb`。

1. 聚焦 M3a：

   ```powershell
   & $godot --headless --path . --log-file .godot\test-logs\m3a-review-focused-20260904.log --script res://tests/run_m3a.gd
   ```

   退出码 `0`；`22 tests / 5632 assertions / 0 failures`。

2. 常规全量（按用户最新要求排除 1000 场 M2 稳定性 suite）：

   ```powershell
   & $godot --headless --path . --log-file .godot\test-logs\m3a-review-regular-20260904.log --script res://tests/run_regular_without_stability.gd
   ```

   退出码 `0`；`239 tests / 9436 assertions / 0 failures`；输出明确为 `OMITTED BY USER REQUEST: res://tests/m2_battle_stability_test.gd`。

两个日志均已扫描 `SCRIPT ERROR|Parse Error|Invalid|Assertion failed|FAIL:`，无匹配。`git diff --check` 无输出。

## 范围审计

本批相关生产代码位于允许的 `core/card_*`、`data/definitions/card_definition.gd`、`data/catalogs/card_catalog.gd`、`systems/cards/hand_runtime.gd` 和 `autoload/hand_manager.gd`；相关测试为 `card_catalog_test.gd`、`hand_manager_test.gd` 及 M3a/常规运行入口。`docs/parity-checklist.md` 中仅 R-012 至 R-015 具有“已测试”状态。

工作树在本批开始前已包含大量 M1/M2 未跟踪产物和既有修改；其中 `tests/run_all.gd`、`tools/run_headless_tests.ps1` 不在 M3a 默认范围，但其现有 diff 是先前通用测试运行器/编译失败自测支持，未在本次审查中修改，且任务索引已记录工作树带有用户改动。由于该基线不是干净工作树，无法仅凭当前 `git status` 将这些既有 diff 归因给 M3a；中枢提交时应继续按实际任务归属拆分。

## 未覆盖或环境限制

- 未运行 `m2_battle_stability_test.gd`（1000 场稳定性回归），这是用户明确要求；属于未验证，不是验证失败。
- Godot 启动输出了 Windows 根证书读取失败，以及 `user://.godot/test-logs` 建目录提示；两次运行仍写入项目 `.godot/test-logs`、以退出码 0 完成，且错误模式扫描无产品脚本/解析/断言失败。

## 门禁交接

M3A_GATE 代码可行性门禁通过，可由模块中枢按迁移规则进入 M3b；M3 最终玩法与数值验收仍待后续批次整合。
