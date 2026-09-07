# M3 独立 Review 任务书

## Review 角色

- 建议模型：`gpt-5.6-terra`
- 建议思考强度：high
- 必须由未参与对应实现的独立 agent 执行
- Review 不修改生产代码，不替执行者修复问题，不自行扩张玩法设计

派工消息只需提供本文件路径与审查模式：`M3A_GATE` 或 `M3_FINAL`。所有详细范围以本文件为准。

## 开始前必读

1. 仓库根 `AGENTS.md`
2. 仓库根 `docs/migration-plan.md`
3. 本工程 `docs/m1-m2-handoff.md`、`docs/parity-checklist.md`
4. 本目录 `00_m3_card_gameplay_index.md`
5. 审查模式对应的执行任务书、实际 diff、相关当前代码与测试

只看当前最终代码产物与证据；不参考过往 M1/M2 的细碎分工方式。

## Review 权限与边界

Review 只检查代码可行性：

- GDScript 解析/加载、明显运行风险。
- 接口是否真的连通、资源/路径/Autoload 是否存在。
- 卡牌纯运行时、HandManager、战斗桥与 M2 的分层边界。
- deck RNG 是否独立，卡牌实例身份与四区状态是否可守恒。
- 玩家桥是否存在双调用、重入、失败伪回滚或敌方误接入风险。
- 指定测试是否能真实运行、断言是否覆盖声称的路径。
- 工作树是否混入越界改动，交接文档是否与代码一致。

Review 不深入裁决玩法逻辑、数值和平衡；R 条目与 Q 决议是否符合设计由模块中枢整合。若发现实现与任务书明文接口冲突，可作为代码/接口问题报告。

默认只读。若需要保存 Review 结果，只允许新增 `docs/agent_tasks/m3/reviews/<mode>-review.md`，不得修改任何生产代码、测试或既有文档。

## 模式 A：M3A_GATE

审查 `01_m3a_card_model_and_piles.md` 的交付，重点：

- CardDefinition/CardInstance 是否分离，`instance_id` 是否唯一且稳定可追踪。
- CardCatalog 是否引用 M1 数据而非复制第二份效果/数值事实源。
- Q8 是否只在卡牌层排除 `basicDamage`，且未越界删除 M1/M2 底层定义或破坏既有回归。
- HandRuntime 是否可脱离 SceneTree/Autoload 无头运行；HandManager 是否只是薄适配。
- draw/hand/discard/exhaust 是否只有单一受控变更入口，失败时是否零变更。
- 满手抽牌失败、重洗、end-turn、特殊去向是否存在丢卡/复制卡风险。
- `deck` RNG 是否与 combat/enemyPolicy 隔离，测试是否能发现串流污染。
- 队列重入/拒绝路径是否可测试且不消费 RNG。
- M3b/SP/能量/UI/M5 是否被提前实现。

必须实际运行任务书要求的聚焦测试和常规全量回归。M3 聚焦 runner 不应包含完整 RNG golden，只核对 deck 流隔离和确定性牌序；不运行 1000 场稳定性回归。结论只有：

- `PASS`：无阻塞性代码可行性问题，可进入 M3b。
- `FAIL`：列出按严重度排序、可定位到文件/行/测试的阻塞问题。

## 模式 B：M3_FINAL

审查完整 M3 交付，除 M3A 项外重点检查：

- `CardCombatBridge` 是否为唯一玩家入口，是否按验证/实付/支付/单次效果/去向/事件与充能顺序执行。
- validator/preflight 是否真能保证零变更；提交后失败是否显式停止而不是伪回滚/重试。
- 是否复用了 M2 EffectRegistry，而没有卡牌层重复伤害计算。
- 玩家所有能量来源是否汇聚到同一满阈值生成逻辑；敌方是否保持旧式路径。
- 大招入手/draw top、清能、0 费/消耗/不回能与回合时序是否存在明显接线风险。
- 牌库装配是否保留重复自由技、排除骑士被动卡且仍正确计算 N。
- 所有卡牌暴露/装配/玩家出牌入口是否都排除 `basicDamage`，伪造输入是否在提交前安全失败。
- 结束回合、M2 resolver、下一轮抽牌是否只有一个职责拥有者；终局是否停止。
- `RoundResolver` 的 deferred M3 obligations 是否已落地且没有双执行。
- M4/M5 是否越界，`docs/m3-handoff.md` 是否与实装和测试一致。

必须实际运行所有 M3 聚焦测试、原 M2 关键回归和常规全量测试；不运行 1000 场稳定性回归，不要求在 M3 runner 重复完整 RNG golden。

## 报告格式

1. `Review mode` 与结论 `PASS`/`FAIL`。
2. Findings：按阻塞/高/中/低排序；每条含文件、行号、实际风险、复现或证据。无问题写“无阻塞 findings”。
3. 实际运行的命令及退出码、测试数、断言数、失败数。
4. 范围审计：生产文件、测试、文档是否落在允许范围；列出任何越界。
5. 未覆盖或环境限制：必须区分“未验证”与“验证失败”。
6. 交给中枢的门禁结论，不对玩法/数值作最终验收措辞。

Review PASS 只表示代码可行性门禁通过，不等于 M3 最终玩法验收；最终结论由模块中枢整合。
