# M1+M2 数据与战斗内核交接

## 状态

**已测试，待总集成验收。** 本文汇总 Web → Godot 迁移中 M1 数据层与 M2 无卡牌战斗内核的当前证据，不表示已经上线，也不把模块自评写成“已验收”。规则状态的逐项口径见 `docs/parity-checklist.md`。

## 范围与明确排除

本批覆盖：

- M1 `data/` 全量目录：tuning、events、Buff、弈者、兵种、自由技、专属技、大招、遗物、敌方特性、关卡与肉鸽静态目录。
- M2 无卡牌战斗内核：contexts/stats/damage、Buff 与灼烧、遗物/内容 hook、敌方特性、目标选择、永久成长草稿、11 个自由技 handler、18 个英雄能力 handler、敌方旧式 AI、棋子攻击与命中后反应、Fate、胜负、回合编排和运行时装配。

明确排除：

- M3 玩家卡牌、手牌/牌堆、玩家 SP 付款、行动 quota、玩家 pending ultimate/ultimate decision；M2 只在结果中报告相应 deferred obligations。
- M4 Node、场景、UI、动画、视觉事件消费者与倍速表现。
- M5 肉鸽运行流程、持久化接入及任何对长期 Run 存档的提交；永久成长目前只写入注入的 battle/run draft，不做 I/O。
- 本批不修改 Web 权威实现，不复制第二套 Damage/Buff/Relic/PieceAttack 算法。

## 权威实例与共享接口

`BattleRuntime` 是无 Node/Autoload 的 M2 composition root，并保留以下强引用：

| 权威 | 共享约束 |
| --- | --- |
| `BattleState` | 同一 live battle 使用同一 canonical Dictionary；runtime 不复制出第二份可分叉战斗状态。 |
| RNG | `combat_rng` 与 `enemy_policy_rng` 都是 M0 确定性 RNG，必须为两个不同 exact instance；禁止 global RNG。 |
| `EffectRegistry` | 一次性原子合并 `FreeSkillEffects` 与三个 hero-effect 模块；集合必须恰好等于 M1 catalog 引用的 11 + 18 = 29 个 handler。 |
| `CombatPorts` | actions/services 使用闭合 ID；canonical result 必须二选一为 `{ok: true, value}` 或 `{ok: false, error}`；damage/buffs/relics service 必须与 runtime 所持实例相同。 |
| `DamagePipeline` / `BuffSystem` / `BurnSettlement` | Damage 与 Buff 只各有一套权威；Burn 通过同一 DamagePipeline 以 delayed context 结算。 |
| `HookDispatcher` / `RelicSystem` | runtime、ports、round request 共用同一 dispatcher/relic authority；EnemySkillPolicy 取到的 relic 也必须是该 exact instance。 |
| `PermanentBuffStore` / `GrowthPort` | store snapshot 只读进入战斗；GrowthPort 的 4 个 action 原子合入外部 actions，ID 冲突即构造失败。 |
| `EnemySkillAdapter` | 敌方保留 Web 旧式选技、SP、能量和大招顺序；不接玩家卡牌层。 |
| `PieceAttack` / `PieceReactions` | PieceAttack 负责目标/命中/职业循环，并在每次 canonical primary hit 后调用 reactions；不重复实现 Damage/Buff。 |
| `FateSystem` / `BattleOutcome` | Fate 使用明确侧与注入 RNG；Outcome 独立处理有效单位与 settled 状态。 |
| `RoundResolver` | 敌方弈者 → 双方 slot 1..6 棋子 → enemy/ally burn → finalize；trace 为 JSON-safe，M3 obligation 仅描述。 |
| `BattleRuntime` | 对外只发布有效的完整对象图和薄 `resolve_round`；构造失败不得触发 action、RNG、hook、state 或 run draft 写入。 |

遗物效果仍通过 `external relic actions` 执行具体上层动作；runtime 验证这些 action 为有效 Callable 并把它们接入唯一 RelicSystem，但不在 composition root 内复制其业务算法。

## 分批实现与独立 Review

下表记录各执行批的独立 `gpt-5.6-terra` Review 结论。Review 只检查解析/可运行性、接口、分层、明显运行风险和指定测试；玩法逻辑由模块中枢依据迁移计划、Web 权威规则和测试结果判断。

| 批次 | 内容 | 独立 Terra Review |
| --- | --- | --- |
| M1/A1 | M1 静态目录、定义、引用校验与总目录原子集成 | PASS |
| B0 | canonical contexts、stats、DamagePipeline | PASS |
| B1 | 战斗 Buff、BurnSettlement、PermanentBuffStore | PASS |
| B2 | HookDispatcher、RelicSystem、EnemySpecialSystem | PASS |
| B3-0 | BattleState、CombatPorts、EffectRegistry 合同 | PASS |
| B3-1 | Web 目标选择与稳定 tie-break | PASS |
| B3-3 | 11 个自由技 handler 与窄执行计划 | PASS |
| B3-4 | Permanent growth 纯计划与 GrowthPort | PASS |
| B3-5A | Flame/Fate 英雄效果 | PASS |
| B3-5B | Marshal/Fist 英雄效果 | PASS |
| B3-5C | Siege/Puppet/Shadow 英雄效果 | PASS |
| B3-6 | 敌方旧式选技、付费、能量和大招 adapter | PASS |
| B4-1R | 命中后 martyr/enchant/leech/counter reactions | PASS |
| B4-1A | PieceAttack 目标/命中循环、职业被动与计划消费 | PASS |
| B4-2F | FateSystem | PASS |
| B4-2R | RoundResolver 与 M3 deferred boundary | PASS |
| B4-3A | BattleOutcome | PASS |
| B4-3B | BattleRuntime exact composition 与真实整轮集成 | PASS |
| B4-4A | Web Damage golden 生成与 Godot exact replay | PASS |
| B4-4B | 1000 场短窗稳定性与确定性复放 | PASS |

## 最终证据

### Godot 4.7.1

正式统一日志：`.godot/test-logs/b4-4b-formal1000-hookfix-20260902.log`。

- 全量：`224 tests / 9126 assertions / 0 failures`。
- 架构守卫：`ARCHITECTURE REAL violations=0`。
- B4-4A：`2 tests / 115 assertions / 0 failures`。
- B4-4B：`1 test / 24 assertions / 0 failures`。
- B4-4B 固定根 seed：`M2-BATTLE-STABILITY-2026-09-02-v1`。
- B4-4B 摘要：`requested=1000 completed=1000 settled=1000 errors=0 timeouts=0 nonFinite=0 negativeHp=0 hookErrors=0 replayed=3 digest=163941872 wallMs=491143`。
- 终局分布为 `win=730 / loss=270`；该 harness 只验证短窗稳定性与复放，不是平衡样本，不能解读为胜率或平衡结论。

Damage golden：

- schema/fixture：`schema_version=1`，`fixture_id=web-m2-damage-golden-v1`。
- root seed / stream：`M2-DAMAGE-GOLDEN-v1` / `combat`。
- 6 个固定顺序 case：plain direct、crit、block、crit→block RNG 顺序、lethal/death callback、delayed/no-RNG。
- fixture SHA-256：`42DBD137782832744B0DF7ECC8C5D1ABFDD9AFEE01B3CEE9CBF49DAED27CCD11`。
- 生成器动态导入 Web `scripts/core/damage.js`、`contexts.js`、`random.js`，不在生成器或 Godot 测试中复制伤害公式。

### Web 定向回归

实际执行命令：

```powershell
node --test scripts/tests/battle-contexts.test.mjs scripts/tests/relics-specials.test.mjs scripts/tests/free-skills.test.mjs scripts/tests/content-dispatcher.test.mjs
```

结果：`47 tests / 47 pass / 0 fail`。这里只声明上述四个定向文件，不推断 Web 全仓测试已全绿。

## 提交与失败语义

- 构造器和可静态检查的请求在首次 mutation、action、RNG 或 hook 前完成闭合 preflight；依赖身份、handler 集合或 action collision 不合法时原子拒绝。
- 运行期遵循 sequential commit：Damage、event、reaction、round step 等按 Web 顺序提交；后续 callback/adapter 失败返回明确错误与已提交 trace/prefix，不伪造回滚。
- 永久成长采用 preview/stage 边界；写入的只是注入草稿，不等于 M5/M6 持久化成功。
- RoundResolver 在非终局 finalize 中只报告 `reset_player_action_quota`、`clear_pending_ultimate`、`resolve_ultimate_decision` 为 `deferred_m3`，不新增或修改这些 M3 字段。

## 已知风险与未决事项

- `BattleOutcome` 当前显式保持 Web 兼容：双方同时有效单位归零时判 `win`。这是已测试的兼容策略，仍待产品决定是否改为平局或其他规则。
- `battleStart` 尚未接入本轮 composition/round 入口；上层战斗会话需要在未来明确唯一触发时点。
- external relic actions 由上层提供。W-027【奥术导体】现有测试验证公式与 `deal_relic_damage_to_all_enemies` action 边界，但未逐敌验证真实伤害；W-030【余烬风暴】验证 hook/suppression 边界，但未逐项验证扩散层数与立即结算。因此两条在 parity checklist 中保持“未开始”。
- Damage golden 只有 6 个权威 case，不覆盖全部 Buff、遗物、PieceAttack、round trace，也不覆盖所有浮点边界；不得把它表述为整套战斗 Web golden。
- 1000 场稳定门禁为成本受控的两回合上限短窗；每回合执行一次敌方技能选择，单场最多两次（正式摘要为 `totalRounds=1106 maxRounds=2 enemyPolicyRngDraws=1106`）。它证明无崩溃/非法数值与固定复放，不证明长局终局分布或平衡。
- 该稳定门禁耗时 `491143 ms`，约 8 分 11 秒。共享 Godot user/log 目录的并发运行曾有环境碰撞风险，正式运行应串行并使用唯一绝对 `--log-file`。
- 正式日志唯一环境异常是 Windows 根证书读取失败：`Failed to read the root certificate store`。它不计产品失败；仍须单独扫描 `SCRIPT ERROR`、`Parse Error`、`Invalid`、`Assertion failed` 与 `FAIL:`（不要用裸 `Assertion`，否则会误命中正常的 `assertions=...` 汇总行）。
- M3 玩家卡牌/付款/quota/pending ultimate、M4 表现、M5 肉鸽与持久化均未由本交接提前实现或验收。

## 可复现命令

以下命令从 Godot 项目根目录执行，并在启动前验证本机目标 Godot 4.7.1 绝对路径。

```powershell
$project = 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版'
$godot = 'C:\Users\heliashi\Desktop\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { throw "Godot 4.7.1 executable not found: $godot" }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$log = Join-Path $project ".godot\test-logs\m1-m2-handoff-$stamp.log"
& $godot --headless --path $project --log-file $log --script res://tests/run_all.gd
```

Damage golden 重新生成与哈希：

```powershell
$project = 'C:\Users\heliashi\Documents\弈者卡牌版\弈者卡牌Godot\弈者卡牌版'
$webRoot = 'C:\Users\heliashi\Documents\新弈者\Html'
node "$project\tests\fixtures\generate_web_m2_damage_golden.mjs" --web-root $webRoot --output "$project\tests\fixtures\web_m2_damage_golden.json"
Get-FileHash "$project\tests\fixtures\web_m2_damage_golden.json" -Algorithm SHA256
```

正式日志扫描：

```powershell
Select-String -Path $log -Pattern 'SCRIPT ERROR|Parse Error|Invalid|Assertion failed|FAIL:'
```

本轮文档收敛未创建 Git commit。
