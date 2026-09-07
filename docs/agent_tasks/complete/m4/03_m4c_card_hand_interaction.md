# M4-3 卡牌与手牌交互

## 目标

建立卡牌/手牌可实例化场景，支持扇形排布、7 张边界、悬停放大、拖拽出牌/取消、费用与不可用反馈，并只通过 M4 Command 发出出牌请求。

## 允许范围

- `scenes/cards/**`
- `ui/cards/**`
- 本批专属 `tests/**`

## 禁止范围

- 不修改 M3 运行时、`app/**`、`scenes/battle/**`、`ui/battle/**`、特效目录或主场景。
- 不在 UI 重新实现 SP、validator、目标或伤害规则。
- 首版卡牌均无目标，不增加选目标流程。
- 不复制 STR 的 Global/ActionHandler/FileLoader/mod 依赖。
- 不以脚本 `Control.new()` 拼卡牌结构。

## 依赖

- `M4_CONTRACT` Review PASS。
- 阅读 STR `Hand.gd`、`Card.gd` 与 `Card.tscn`，只借鉴排布/交互形状。

## 实现要求

1. CardView 场景至少展示名称、说明、费用、类别、归属、消耗/回手等关键标签与不可用原因。
2. HandView 根据 VM 中稳定 `instance_id` 做增量实例化/释放和顺序同步。
3. 1–7 张按容器宽度自适应扇形排布；卡牌中心、旋转、Y 偏移来自可调 Curve/Resource 或导出参数。
4. 悬停提高 z_index 并放大/抬升；离开时恢复布局。
5. 拖过有效出牌阈值才发 Command；取消拖拽回到原位。队列忙、fatal、非 player_input 或 VM 不可用时不能发 Command。
6. 不可用卡灰显并显示权威原因；不能仅用费用颜色代替完整禁用状态。
7. 发出的请求只携带权威 VM 给出的 instance/card/source/owner guard，不直接移动或删除视觉卡；收到新 VM 后再同步。

## 完成条件

- `hand_ui_test.gd` 覆盖 1/3/7 张布局边界、悬停层级、拖拽成功/取消、队列锁、不可用不发 Command、同名卡不同实例。
- 1200×700 的手牌区域中 7 张卡完整可操作且不越界。
- 场景实例化守卫确认卡牌来自 `PackedScene`。
- 测试可使用静态 VM/Command spy，不依赖主场景。
- 回报修改、测试与交互风险，不自行验收或提交。
