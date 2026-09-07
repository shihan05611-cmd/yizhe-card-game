# M4-4 技能特效编排与节点播放器

## 目标

迁移 Web `skill-fx.js` 已存在的声明式时间轴语义，并用 Godot 预制节点场景重写播放器；不迁移 DOM/CSS，不在代码中即时绘制原语。

## 允许范围

- `data/presentation/**`
- `scenes/effects/**`
- `ui/effects/**`
- Web 现有拳影素材复制到 `assets/effects/punch-shadows/**`
- 本批专属测试

## 禁止范围

- 不修改 Web 工程。
- 不修改 M1–M3 规则、`app/**`、战斗/卡牌场景或主场景。
- 不新增大规模原创美术，不把 Web CSS 逐条翻译。
- 不使用 `_draw()`/`draw_*()` 生成正式特效。
- 不因缺少专属编排而阻塞战斗逻辑。

## 依赖

- `M4_CONTRACT` Review PASS。
- 完整阅读 Web `scripts/data/skill-fx.js`、`scripts/ui/skill-fx-player.js` 和 `scripts/tests/skill-fx.test.mjs`。

## 实现要求

1. 迁移现有 `fist`、`shadow`、`ascend`、`burn01`、`burnEnchant`、`puppet` 六项大招编排的结构语义、标题和关键阶段。
2. 提供 timeline resolver、1500ms cap、reduced-motion 简化时间轴和 1x 基础时长；倍速缩放由后续队列注入统一 clock。
3. vignette、caption、burst、beam、streak、multi-target、field 等每种原语均由独立 `.tscn` 实例化。
4. 目标定位消费稳定 side/slot 或 hero_id，不保存业务节点引用到数据层。
5. `shadow` 保持 start 锁定、显式 end 后斩击的两阶段结构；`fist` 残影数量随 hits 单调变化。
6. 未有专属编排的技能走一个轻量通用节点场景；未知 event 安全忽略并记录诊断，不影响逻辑。

## 完成条件

- `skill_fx_catalog_test.gd` 对齐 Web 结构性测试：早期 caption/vignette、时长 cap、fist 动态残影、shadow 两阶段、未知 key、reduced motion。
- `skill_fx_scene_player_test.gd` 验证所有原语由 PackedScene 实例化、multi-target 锚点和清理行为。
- 正式特效脚本无 `_draw()`/`draw_*()`/动态 Control 树拼装。
- 回报修改、测试、已迁移条目和未编排条目，不自行验收或提交。
