# M4-2 战斗场景、棋盘与 HUD

## 目标

建立由可复用 `.tscn` 节点组成的战斗场景骨架，展示双方 2×3 棋盘、SP、弈者能量、牌堆计数、日志、结束回合、终局与 fatal 状态。

## 允许范围

- `scenes/battle/**`
- `ui/battle/**`
- 既有 Web 立绘复制到 `assets/portraits/**`
- 本批专属的场景实例化、布局和 ViewModel 绑定测试

## 禁止范围

- 不修改 `app/**`、M1–M3 规则、`scenes/cards/**`、`ui/cards/**`、`scenes/effects/**`、`ui/effects/**`。
- 不修改 `scenes/main.tscn`。
- 不做地图、商店、奖励、存档。
- 不用脚本即时绘制正式 HUD/棋子；不追求像素级美术定稿。

## 依赖

- `M4_CONTRACT` Review PASS。
- 只消费 M4-1 ViewModel/Command 合同；测试可注入静态 VM。

## 实现要求

1. 至少拆出 BattleScreen、BoardGrid、PieceSlot、HeroEnergyPanel、BattleHud、CombatLog、BattleResultOverlay/FatalOverlay 等可实例化场景。
2. 每侧固定六槽，空位仍保留稳定锚点；槽位顺序与 M2 `slot` 1–6 一致。
3. 棋子节点展示阵营、编号/职业、HP、Buff/标记和存活状态；弈者节点展示姓名、立绘、能量值/上限。
4. HUD 展示 round、SP、draw/discard/exhaust/hand 数量、1x–4x 状态、自动战斗状态和结束回合入口占位。
5. 日志使用可实例化条目或预置容器绑定，不在每帧重建整个节点树。
6. fatal/终局遮罩明确禁用继续操作，具备重新开始同一演示战斗的 UI 插槽，但本批不自行实现 bootstrap。

## 完成条件

- 所有场景可单独实例化，无缺失 NodePath、脚本或资源。
- 1200×700 下双方棋盘、HUD 与预留手牌区无明显遮挡或越界。
- 静态 VM 可驱动血量、能量、Buff、日志、终局/fatal 变化。
- 立绘沿用 Web 现有素材；缺少立绘的弈者用场景内占位节点，不生成新美术。
- 测试覆盖六槽锚点、VM 更新复用节点、终局/fatal 输入锁和正式 UI 禁止即时绘制。
- 回报修改、测试和明显布局风险，不自行验收或提交。
