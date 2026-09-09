# 弈者选择与状态反馈补充

本轮承接用户的新要求：弈者统一三选一并展示立绘、遗器图形展示、新局甲卒居中、完整状态栏，以及格挡与暴击的兼容反馈。

## 设计取舍

- 初始选择与旅途招募采用相同的三列结构，使用已有角色立绘。专属技摘要与确认按钮跟随对应角色，详细说明保留可访问入口。
- 遗器复用已接入的代码图标，延续无明显框线、以留白组织的风格。
- 新局六槽为 `[null, shield, null, assassin, crossbow, banner]`。甲卒独占前排中间，后排依次为刺客、机弩、旗兵；现有存档部署保留。
- 状态信息与效果动画分开：没有独立动画的 buff 仍须显示状态，阵营效果须明确归属。
- 每次命中显示一个实际伤害数字，暴击与格挡可以同时标记，完全格挡保留零伤害反馈。显示层使用既有结算数据。

## 验证记录

- Run/M5 聚焦回归：48 tests / 2949 assertions / 0 failures，日志 `.godot/test-logs/three-choice-m5-final.log`。
- 阵型与旧存档补充套件：4 tests / 66 assertions / 0 failures，日志 `.godot/test-logs/run-formation-final.log`。覆盖实际旧第四候选已选中、多成长候选、非法第四候选/多余 authority 拒绝、真实旅程到达招募后恢复旧四选项并成功招募。
- 常规回归其余 405 项测试、14402 条断言通过；该轮唯一失败是正在新增的存档测试套件无法加载，修正类型声明及真实招募夹具后，上述独立套件已完整补跑通过。常规日志 `.godot/test-logs/hero-status-regular-final.log` 保留当时失败，不将其记为零失败全量运行。沿用既有约定，未运行千局稳定性套件。
- M4 聚焦回归：44 tests / 803 assertions / 0 failures，日志 `.godot/test-logs/status-m4-root-final.log`。新增断言覆盖单体状态的事件增删、缴械回合、阵营状态的归属与过期、完整悬停信息、完全格挡显示零、暴击与格挡组合标记、伤害权威值与重复 envelope。
- M4 E2E：5 tests / 1715 assertions / 0 failures，日志 `.godot/test-logs/hero-status-e2e.log`。1× 与 4× 均提交 46 条命令、产生 780 条事件，演出时长比为 4.000。
- 实际窗口的初选、招募与遗器奖励截图已逐一目检：`tests/artifacts/journey/02_choose_hero.png`、`09_recruit.png`、`08_reward.png`。画像扩大为 160px，去掉内框，选择按钮底部齐平；遗器奖励去除重复标题，三项同屏。
- `tests/capture_run_formation_drag.gd` 的真实鼠标输入测试通过：后排刺客与居中甲卒交换，再从库存拖入旗兵替换原甲卒，`FORMATION DRAG failures=0`。
- `tests/capture_relic_formation_ui.gd` 不再注入旧默认阵型，改为通过真实新局验证甲卒居中；普通战斗和精英空位截图均生成成功。
- `tests/capture_status_feedback.gd` 使用真实 Run 单位和 BuffSystem 施加状态，再以显式命中事件验证组合伤害画面。截图 `tests/artifacts/inkjade_relic_formation/03_status_feedback.png` 是展示测试夹具，不能视为一次完整对局的自然触发记录。
- Windows Portable Pack 已更新到 `build/YizheCardGame`，导出日志 `.godot/test-logs/hero-status-build-final.log`。打包后的游戏启动验证日志为 `build/YizheCardGame/logs/hero-status-smoke.log`；仅有本机根证书提示。导出工具另有沙箱不能保存系统编辑器设置的提示，不影响 PCK 生成。

## 兼容与实现归属

- 旧存档恢复时，四个候选确定性收束为三个，保留已有初始弈者与成长候选的必要条件；不消耗额外随机数。裁剪前验证完整旧候选与对应 authority，避免丢弃非法第四项后误接受坏存档。
- 三选一、默认站位、立绘/遗器 UI 与状态接线由 Terra 子代理执行，root 负责画面审查、修正状态悬停与布局边界、补充集成验证及收口。
- 本轮复用之前由 GPT-6 绘制的遗器图标与灼烧效果，没有新增代码绘制美术。其余 buff 本轮只有状态信息，没有新增专属粒子或动作。
