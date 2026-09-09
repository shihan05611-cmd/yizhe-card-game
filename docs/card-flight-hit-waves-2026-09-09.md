# 出牌移动、敌方弈者层数与群攻表现

本轮实现用户提出的三项改动，保留卡牌拖拽与既有伤害结算规则。

## 验收目标

- 出牌从实际释放位置平滑移入右侧结算区，等待中的牌也要有明确去向；暂停、倍速及队列刷新不能导致突然归位或残留副本。
- 第一层敌方只有军令，第二层增加铁卫，第三层增加千机。使用已有角色能力，覆盖 Run 普通、精英及关主战斗。
- 单段群攻对所有目标同时展示命中、伤害与血量变化；宁不凡大招保留多段节奏，不能按同一张牌把多段合成一次。

## 实施与验证

- 出牌记录松开鼠标时的实际位置、旋转与缩放，首次进入队列就开始约 0.32 秒的平滑移动（按演出倍速缩短）。队首飞向完整预览，等待牌收束到自己的牌签；超过展开数量的牌移向剩余数量标记。飞行期间对应静态卡隐藏，到位后显示，不再叠加一个立即出现的预览。
- 队列刷新保留在途卡片，并动态读取当前目标位置；取消或终局移除条目时清理飞行对象。飞行 Tween 绑定卡片节点，随父场景暂停。
- Run bootstrap 按章节使用已有军令、铁卫、千机的累积名单，保留现有能力与数值；独立 M4 调试战斗仍使用原舞台配置。
- 技能主伤害使用显式段编号分组；赤焰群攻和宁不凡拳劲同段命中同时展示，宁不凡大招每击使用递增编号。棋子多目标普攻复用真实攻击动作 ID，同一次攻击一起展示。反击、追击与副事件分别保留，不把整张牌的全部伤害粗略合并。
- 全量常规回归：411 tests / 14499 assertions / 0 failures，日志 `.godot/test-logs/flight-wave-regular.log`。沿用既有约定跳过千局稳定性套件，E2E 单独运行。
- 群攻与多段专项：26 tests / 491 assertions / 0 failures，日志 `.godot/test-logs/damage-wave-handlers.log`。覆盖真实伤害处理器的段编号及队列分组、独立反击、1×/4×比例。
- Run 专项：49 tests / 2961 assertions / 0 failures，日志 `.godot/test-logs/run-enemy-yizhe-m5.log`。
- 三层真实 Run 截图：`tests/artifacts/run_enemy_rosters/chapter_1.png` 至 `chapter_3.png`，从实际 lifecycle 逐章推进，经 bootstrap/controller 生成界面，已目检人数与名称。
- 飞行截图：`tests/artifacts/card_arrival/01_release.png`、`02_in_flight.png`、`03_arrived.png`，通过实际 CardView 拖拽接口生成，已目检起点、中途与终点。取证期间只冻结结算队列推进，以便记录同一张卡片的移动过程。
- 飞行专项 `tests/run_pending_card_flight.gd`：25 assertions / 0 failures，日志 `.godot/test-logs/pending-card-flight-final.log`。验证旋转/缩放后的精确起点、终点矩形与静态卡一致、刷新不复制或销毁在途卡、暂停冻结、取消清理，以及真实 MainScene 两次拖拽会立即创建两条飞行但只提交第一张。修复了设置旋转/缩放顺序引入的 pivot 位置偏移。
- 自动战斗 E2E：5 tests / 1715 assertions / 0 failures，日志 `.godot/test-logs/flight-wave-e2e.log`，1×/4×结算结果一致，46条命令、780条事件，时长比4.000。
- Windows 包已更新至 `build/YizheCardGame`；最终导出日志 `.godot/test-logs/flight-wave-build-final.log`，打包启动日志 `build/YizheCardGame/logs/flight-wave-smoke.log`，启动退出码0，无脚本错误。仅保留本机根证书及导出时无法写系统编辑器设置的环境提示。

## 实现归属

Terra 子代理完成敌方配置、伤害分组与飞行组件初稿；root 负责飞行与首次入队接线、动态目标和静态预览连续衔接、溢出队列目标、实机审查与集成验证。本轮复用已有卡牌美术，没有新增代码绘制图形。
