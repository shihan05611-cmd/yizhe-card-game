# 可玩版本交接

日期：2026-09-08。本文记录当前实现，替代旧 M5 暂停步骤；M0–M5 原始交接保留作历史依据。

## 当前运行入口

- `project.godot` → `scenes/run.tscn`：标题、开始/继续、选人、三章地图、招募/部署、战利品、商旅、锻坊、奇遇及整局结果。
- `ui/run/run_screen.gd` 负责界面组合和输入；`ui/run/run_map.gd` 显示领域提供的地图、路径和可达节点，不另算前沿。
- `app/run_session.gd` 负责目录展示投影、领域命令和节点检查点；经济费用/恢复可用性来自 lifecycle 返回值。
- `scenes/main.tscn` 保留为可复用的单场战斗场景及旧测试入口。`BattleSceneCoordinator.start_run_battle()` 使用真实 Run adapter，动画播完后再结算；结果按钮继续旅程，不重开同一 Run 战斗。
- 应用命令前刷新生命周期状态，避免 adapter 已结算而应用缓存仍为 fighting 导致奖励被拒绝。

## 原生代码美术

用户指定源是 `tools/art/studies/geometry-crossbow-projectile.html`，选用右侧 `piece-geometry-v4.js`。

- `ui/art/geometry_piece.gd` 将几何轮廓、厚度、玉石/陶土配色、固定矿物颗粒和动作转为 Godot 绘制。
- 甲卒、机弩、刺客、旗兵沿现有职业 VM 显示；不更改职业属性或战斗规则。
- 机弩主体稳定，弹丸独立向前飞行并消隐，不随身体归位倒飞。身体和弹丸使用既有表现事件时长，服从倍速。
- 角色立绘继续使用 `assets/portraits/` 中的已有图片，并包含在导出包中；`hero_energy_item.gd` 按角色 ID 显示，缺少图片时使用原文字占位。此前将角色误替换为几何印章的改动已按用户反馈撤回，几何绘制仅用于棋子。
- 美术、UI 设计与绘制由主助手 GPT-6 执行；Sol/Terra 承担存档、非视觉应用接线、真实运行缺陷排查、文档和打包。
- 棋盘显示已按前后排镜像校正：规则槽位 `1–3` 均在靠中线的前排、`4–6` 在后排；我方视觉行依次为 `[4,1] [5,2] [6,3]`，敌方为 `[1,4] [2,5] [3,6]`。这只重排现有 Control，VM 槽位、攻击规则与目标锚点仍按原 slot id 解析。

## 保存与恢复

首版保存到 `user://run-save.json`，仅保存节点间状态。进入节点前确认地图检查点写入成功；战斗中关闭游戏或暂停退出，继续游戏回到入战前。

保存内容包括闭合版本号、Run 状态、奖励/商店私有选项、确定性随机源和 rollback replay。回放浮点以可逆表示持久化，读取时校验并规范化 JSON 数字。重复购买和领奖继续由领域权威拒绝。

`RunSaveStore` 使用临时文件和备份替换；支持写入中断后从有效备份恢复并继续保存，损坏文件留作诊断。无法保存会显示可重试提示；已经生效的普通命令不会因写盘失败被误报为领域失败。

## 玩家操作

- 标题页开始新的旅程或继续存档；新旅程替换已有存档前会确认。
- 地图点击亮起节点；左侧可在地图阶段调整弈者空闲站位、查看各槽生命及牌库/遗物。
- 卡牌拖向棋盘出牌，结束回合推进敌方与棋子行动；可选自动战斗和 1–4 倍速。
- 暂停按钮或 Esc 可暂停；继续战斗恢复原自动战斗设置。
- 商店显示实际折后价格、已购/余额不足状态；锻坊满血时不显示虚假的免费治疗入口。
- 骑士被动专属不显示为主动专属卡；英雄选择和招募提供技能说明。

## 验证与交付边界

本轮恢复后的用户确认：**模拟先不深究，以玩法流程跑通为交付标准**。不继续追查三章胜率、长回合样本或调整平衡数值；已有模拟仅保留为诊断记录。

持久化和应用入口已有独立聚焦测试；整体界面通过 `tests/capture_journey.gd` 在实际 Godot 窗口验证，覆盖真实首战、结果继续、领奖、招募、商店/锻坊/奇遇，以及 1200×700 与 1600×900。截图在 `tests/artifacts/journey/`。

恢复开发后补齐两项历史测试缺口：`ember_storm_runtime_test.gd` 经真实 Run adapter 和伤害死亡 hook 验证低层灼烧不放大、扩散后立即结算（2 tests / 46 assertions）；`battle_restart_isolation_test.gd` 验证旧局 halted/settled、出牌忙碌状态与表现队列不会泄漏到新局，新局能够接受回合命令（1 test / 16 assertions）。两项聚焦运行均无失败。

奥术导体已补通成功卡牌实付 SP 和我方付费超级反击两条事件来源，免费反击/0 SP/拒绝出牌不会误触发；遗物先击杀末敌或反击目标后，当前命令仍能安全完成。专项结果 21 tests / 394 assertions / 0 failures。规则对照表为 79 项已测试、1 项未开始、9 项废弃；唯一未开始项是强制胜利调试入口，不影响正常玩法。

玩法收尾时常规回归：`tests/run_regular_without_stability.gd` **384 tests / 14051 assertions / 0 failures**，退出码 0，日志 `.godot/test-logs/journey-regular-release.log`。日志无脚本解析、运行或资源加载错误；仅本机通用根证书读取提示。

随后按用户反馈恢复角色立绘：ART-2 聚焦回归 **5 tests / 140 assertions / 0 failures**，逐一检查全部 8 位已有立绘角色，缺图角色继续使用文字占位。实际窗口截图 `tests/artifacts/journey/12_restored_portraits.png`；导出配置已重新包含 `assets/portraits/`。

真实三章运行使用 `tests/simulate_real_runs.gd`，仅通过真实战斗命令推进，不预设胜利或写 HP/货币；结果及策略限制见 `docs/real-run-simulation.md`。这与 M5 预设终局的编排测试属于不同证据。

Windows 便携包位于 `build/YizheCardGame/`，由 `tools/build_windows.ps1` 重建。本机没有对应 export templates，因此附带现有 Windows Godot 引擎和 `.pck`，不冒充模板导出的独立 release。运行不依赖源码目录。

本轮最终包已重建，双击 `build/YizheCardGame/启动游戏.cmd` 启动。启动包装脚本的 PowerShell 日志筛选续行错误已修正并同步到包中；从 `C:/Users/78566`（源码目录外）执行 `play.ps1 -HeadlessSmoke` 通过，退出码 0，日志 `build/YizheCardGame/logs/play-20260908-224813.log`。源码与文档保留在工作树，未提交或推送 Git。

本轮未运行 1000 场稳定性，也不把小样本模拟声明为最终商业平衡验收。神通与两件进化遗物继续休眠。
