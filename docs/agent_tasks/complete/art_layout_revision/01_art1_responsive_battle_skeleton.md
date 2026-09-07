# ART-1 响应式战斗骨架

## 目标

将 BattleScreen 的绝对坐标骨架改为容器与叠层组合，建立后续 HUD/日志和手牌组件的稳定插槽。

## 允许范围

- `scenes/battle/battle_screen.tscn`
- 必要的根布局聚焦测试与 runner
- 仅为保持既有节点路径可用而做的 `ui/battle/battle_screen.gd` 最小适配

## 禁止范围

- 不改 Controller、VM、事件合同、队列时钟与战斗规则。
- 不实现日志快捷键、未读角标或 HUD 信息重排。
- 不改卡牌、棋子格、结果层的内部信息结构。
- 不推进第二期 Theme、色板、字体、立绘或 FX。

## 依赖

- M4_FINAL PASS。
- `00_art_layout_revision_index.md` 的合理性决议。

## 实现要求

1. 根结构使用 16 边距、12 段间距；TopBar 与 MainStack 由 VBox 分配。
2. MainStack 内叠加 MainRow、底部渐隐和 HandLayer；HandLayer 不参与 VBox 高度分配。
3. MainRow 为战场扩展区与日志插槽；保留后续抽屉可退出布局的节点边界。
4. 战场为左右镜像双列，每列按标题、弈者面板、2×3 棋盘组织；弈者面板取消固定 194×150/204×184 高度并随人数自适应。
5. 手写 offset 只允许存在于叶子组件内部；BattleScreen 与 Arena 不再用固定坐标拼主布局。
6. 删除 HandReserve 实心底板，改为场景资源定义的底部渐隐暗色；0 手牌时不得出现框体。
7. 保留全部 unique node 名与现有 bind/anchor 行为，正式动态节点仍走 PackedScene。

## 完成条件

- 新增聚焦测试覆盖节点结构、容器 flags、HandLayer 叠层和 1200×700/1280×720/1600×900 基础几何。
- 三档尺寸均无 BattleScreen/Arena 主布局裁切或单侧死空隙。
- 现有 M4 场景与表现聚焦测试通过；未运行 1000 场。

