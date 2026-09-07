# 棋像方案二/三对比样稿

2026-09-05：用户要求两个独立 GPT-6-astra / medium agent 分别实现。只制作样稿，不替换 Godot 当前资源或战斗逻辑。

- piece-option2.js：国际象棋剪影，silhouette_study agent。
- piece-option3.js：几何组合，geometry_study agent。
- piece-options-compare.html：主助手统一对比壳，统一基础配色、尺寸、阵容、动作时间。

通过本地 HTTP 服务打开 HTML（ES module 不适合直接 file:// 打开）。四兵种、敌我、放大与十二枚棋阵；支持同时出手、定格、隐藏名称、去色。两模块均通过 node --check；浏览器实际查看了四兵种及同步动作。没有安排独立 Review。


2026-09-07：机弩静态造型已认可，出手改简约弹丸。piece-geometry-v4.js保持主体稳定，通过独立drawProjectile飞行进度单向发射，不复用往返pose。geometry-crossbow-projectile.html保留与上一动作的对比。已实际查看飞行定格；不改Godot游戏。
