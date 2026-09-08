# Web 端权威参考

## 当前本地来源

- 参考工程：`C:\Users\78566\Documents\ChatGPT\弈者-独立版`
- Web 工程根：`C:\Users\78566\Documents\ChatGPT\弈者-独立版\Html`
- Git 远程：`https://github.com/shihan05611-cmd/NewChessors.git`
- 确认时分支／提交：`main@8d1d15d`

本机目录“弈者-独立版”就是旧设备资料中可能称为“新弈者”的工程。自 2026-09-07 起，Godot 迁移任务中的“Web 源码”“Web 源工程”与“Web 默认规则”均指向上述 `Html` 目录；不得再通过旧目录名“新弈者”定位来源。

## 使用边界

- Web 代码用于行为、数据和 golden fixture 的权威参考，不代表允许修改 Web 工程。
- 未经用户另行要求，不在参考工程中实施迁移、修复、提交或推送。
- 生成 Web golden fixture 时，优先显式传入 `--web-root`，或设置 `YIZHE_WEB_ROOT`；其值均应为上述 `Html` 目录。
- 已完成任务和旧交接材料中的历史绝对路径属于当时的执行证据，不据此选择当前参考源。

## 当前漂移记录

2026-09-07 接力前复核确认：`map-system.js`、`random.js`、`skills.js` 的源码哈希相较旧设备生成时发生变化，其余已核对的 M5 模块保持一致。使用本机当前 Web 根重生成并逐项比较后，M0 RNG 序列与 M5 地图／遭遇 golden 的行为数据均未变化，仅来源哈希、来源路径和生成时间变化；因此刷新 fixture provenance，不修改对应 Godot 行为，M5-04 可按当前 Web 源继续。
