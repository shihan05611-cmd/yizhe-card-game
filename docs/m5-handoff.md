# M5 肉鸽层交接

更新时间：2026-09-08

## 当前结论

M5 的无界面肉鸽领域、经济节点、战斗桥和固定种子三章通关链已经完成 Executor
实现与自动测试。M5-90 独立 Review 首轮发现 Run 战斗六槽职业投影缺口；用户随后
冻结新默认阵容，Executor 完成单点修复，独立 Reviewer 复验后给出最终 PASS。

当前玩家流程保持“无神通”状态。`charge`、`assault`、`sacrifice` 及两件进化遗物
只有目录数据、休眠领域模块和独立测试；Run、`GameRoot`、`BattleController`、UI 与
InputMap 均没有入口。

## 已完成的运行链

- `RoguelikeRunContract` 保存 JSON-safe、闭合的三章 Run 状态，不含神通选择或次数。
- `RoguelikeMapSystem` 生成每章 3×10 地图，并解析普通、精英和 Boss 遭遇。
- `RoguelikeRunLifecycle` 权威处理开局、节点前沿、奖励、招募、商店、锻造、事件和
  三章终态。
- `RoguelikeBattleAdapter` 从 lifecycle 获取一次性 launch，创建真实
  `BattleController`，并通过绑定的 `RunBattleProgress` 提交胜负、六槽 HP 和永久成长。
- 战斗 launch 只投影普通战斗遗物；`shentongAssaultBurst` 与
  `shentongChargeOverload` 会被过滤。
- Run 战斗的默认友军职业按冻结阵容投影：槽 1–3 `shield`、槽 4 `assassin`、
  槽 5 `crossbow`、槽 6 `banner`。职业生命、攻击、格挡/暴击加成先进入战斗状态，
  再叠加永久成长、普通遗物和槽位生命比例；M4 直开配置仍保持六槽 `default`。
- M5 bridge 回归通过真实 DamagePipeline 验证了 `shieldPlus` 的格挡后恢复，并验证
  `crossbowPlus` 只命中槽 5 的 -20 最大生命和 +10% 追击概率。

固定种子 `m5-06-three-chapter-no-shentong` 的无头 E2E 完成 30 个权威节点、三章
Boss、普通遗物奖励、一次商店购买和第一章两次招募。每个经过的战斗节点都走真实
adapter/progress settlement；测试不会向 Run 注入神通或两件进化遗物。

## 休眠神通边界

`DormantShentongDomain` 只接受一个 M1 神通定义、只读遗物 ID、精确 battle port 和
`TransactionalRunRandom`。`DormantShentongBattlePort` 的快照、恢复、视图与 action
集合是闭合边界。直接单测已经覆盖：

- 【蓄势】首行动限制、治疗、延长灼烧、本回合减伤、下回合增伤和进化能量；
- 【强袭】按选中弈者/部署顺序选择施法者，以及临时 3×/进化 5×；
- 【献祭】稳定最低生命比例目标、傀儡/普通奖励差异和 sacrifice death context；
- 三种神通的独立每场次数；
- action、结算和抽取失败时对战斗草稿、领域次数及 RNG replay 的原子回滚。

这些模块目前不得由生产代码 preload 或实例化。自动未接线测试扫描 Run 三个核心
脚本、`GameRoot`、`BattleController`、`project.godot` 与整个 `ui/`；另检查
InputMap action 和 Controller 方法面。

## 未来接线点

未来里程碑若决定开放神通，应显式完成以下工作，不应直接从 UI 调休眠领域方法：

1. 先扩展 Run 合同和存档版本，定义神通选择、每战初始化及恢复语义。
2. 在战斗组合根创建真实 `DormantShentongBattlePort` callbacks，把每个 action 映射到
   现有权威 CombatPorts、回合标记和共享胜负结算。
3. 由单一 Command 入口调用 `can_use/use`，再由 ViewModel 暴露只读可用性与次数。
4. 只有神通选择规则接线并验证后，才允许两件进化遗物进入候选池；仍需保持普通
   reward/shop/forge 过滤规则可审计。

## 后续风险

- 休眠单测使用精确 battle port 替身；真实 action 映射、表现事件顺序和重复结算保护
  必须在未来接线里重新做集成测试。
- M5 是内存态；存档版本、恢复 active option authority 和跨设备迁移属于 M6。
- 当前三章 E2E 验证 Run 编排和真实战斗提交边界，但通过设置终局战斗状态来聚焦
  M5，不替代 M2 稳定性或 M4 玩家操作 E2E。
- 当前设备的 Godot 4.7.1 在沙箱中不能写 AppData editor settings，且会报告根证书
  读取告警；命令必须使用工作区 `--log-file`。这些告警未造成 parse/test failure。

## 可复核证据

- `res://tests/run_m5_06.gd`：累计 M5 阶段 46 tests / 2730 assertions / 0 failures；
  其中 M5-06 新增套件为 7 tests / 711 assertions / 0 failures。
- `res://tests/run_regular_without_stability.gd`：369 tests / 13685 assertions / 0 failures。
- Godot 4.7.1 headless editor parse/import：退出码 0。
- M5-90 独立最终 Review：PASS；报告见 `docs/agent_tasks/complete/m5/reviews/M5-90-review.md`。
- M5-06 不执行 M6 存档、1000 次稳定性、胜率或平衡工作。
