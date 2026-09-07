# M4 独立 Review 任务书

## 角色与模式

Review 为只读角色，不修改实现。调用方必须指定以下一种模式：

- `M4_CONTRACT`：M4-1 完成后的合同门禁。
- `M4_FINAL`：M4-6 完成后的完整代码可行性门禁。

输出结论只能是 `PASS`、`FAIL` 或 `BLOCKED`，并按严重度列 findings。

## 通用检查范围

- `AGENTS.md`、迁移计划 M4、`00_m4_battle_presentation_index.md`、对应任务书。
- 当前 diff/工作树与执行回报。
- M3 冻结接口和 M4 新增的 app/ui/scenes/data/presentation/tests/docs。

## 通用禁止范围

- 不编辑任何文件，不提交。
- 不深入裁决玩法数值或平衡。
- 不以个人美术偏好阻塞；只检查缺失、不可读、明显遮挡/溢出和状态错误。
- 不运行 1000 场回归。

## M4_CONTRACT 检查项

1. 生产 bootstrap 使用真实 M1–M3 runtime，不引用测试 fixture。
2. UI ViewModel 深隔离，Command 不暴露 raw mutation。
3. 卡牌 inspection 与真实预检共享权威且零副作用。
4. `battleStart` 单点触发，fatal 不重试。
5. W-021–W-024/W-037 事件与字段合同可供后续场景消费。
6. 未提前实现正式场景、卡牌 UI、特效或 M5/M6。
7. 指定聚焦测试及常规非稳定性回归可运行。

Review 结果写入 `docs/agent_tasks/m4/reviews/M4_CONTRACT-review.md`。

## M4_FINAL 检查项

1. 场景/脚本解析、NodePath、资源路径、主场景与 autoload 可行。
2. Battle/Card/Hand/FX/Float 等动态视觉由 `.tscn`/PackedScene 实例化；无正式 `_draw()`/`draw_*()` 或大量即时 Control 构造。
3. UI 只消费 VM、只发 Command；没有第二份伤害/validator/牌堆权威。
4. 表现队列串行、输入锁正确，1x–4x 不重复/丢失结算。
5. 自动战斗共用同一入口并可终止；fatal/终局可见。
6. 1200×700 下 7 张手牌和主要 HUD 无明显遮挡/越界。
7. V-001–V-008、W-021–W-024、W-037 的实现和测试证据一致。
8. M4 聚焦、常规非稳定性回归与图形 smoke 可运行；未把 1000 场省略伪报为通过。
9. M5/M6 边界和工作树脏基线被保留。

Review 结果写入 `docs/agent_tasks/m4/reviews/M4_FINAL-review.md`。

## 回报格式

- 模式与结论。
- Findings（文件/行、风险、建议）。
- 实际运行的命令、退出码、测试/断言数字。
- 范围审计、未覆盖项和环境限制。
- PASS 时明确写出下一门禁可启动；FAIL/BLOCKED 时写出最小修复范围。
