# M5 肉鸽层任务书索引

## 已确认边界

- 当前 Web 权威参考为 `C:\Users\78566\Documents\ChatGPT\弈者-独立版\Html`；旧资料中的“新弈者”只是旧目录名，定位与只读规则见 `docs/web-reference.md`。
- M5 只负责无界面的肉鸽领域层、战斗桥接和确定性测试，不制作正式肉鸽 UI。
- 免费技能作为本局牌库中的多重集保存，允许重复，不迁移 Web 的装备技能槽。
- 神通 `charge`、`assault`、`sacrifice` 及其运行时代码需要迁移并独立测试，但暂不接入 Run、GameRoot、战斗控制器或玩家流程。
- `shentongAssaultBurst`、`shentongChargeOverload` 保留目录、效果查询和独立测试，但不得进入 M5 奖励池、商店池或完整通关流程。
- 普通遗物仍由 M5 正常接入奖励、商店、锻造和战斗。
- 不实现 M6 存档、恢复、批量模拟与平衡报告，不进行 1000 次回归。

## 执行顺序

1. `../complete/m5/M5-01-run-contract-rng.md`（已完成）
2. `../complete/m5/M5-02-map-encounter.md`（已完成）
3. `../complete/m5/M5-03-run-lifecycle.md`（已完成）
4. `../complete/m5/M5-04-economy-nodes.md`（已完成）
5. `../complete/m5/M5-05-battle-bridge-progress.md`（已完成）
6. `../complete/m5/M5-06-dormant-shentong-e2e.md`（已完成）
7. `../complete/m5/M5-90-final-review.md`（独立 Review PASS）

M5-02 的地图纯逻辑与 M5-05 中的战斗进度纯数据组件在契约冻结后理论上可以并行，但默认复用同一 Executor 顺序推进，以降低共享 Run 契约反复协调的成本。

2026-09-08 已在新设备完成接力、Web 参考源校正、M5-04～06 实现与 M5-90 独立复审。用户批准的 Run 默认阵容为 `shield ×3 / assassin / crossbow / banner`；最终 Review 结论为 PASS，报告归档于 `../complete/m5/reviews/M5-90-review.md`。

## 阶段门禁

- 每批 Executor 必须实现任务范围内代码、测试并回报证据，不作最终验收。
- 中枢确认前一批契约和测试后，才放行依赖它的下一批。
- M5-90 必须由未参与实现的 Reviewer 执行。
- 已完成任务书及证据在最终收口时移入 `docs/agent_tasks/complete/m5/`。
