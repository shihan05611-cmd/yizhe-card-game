# 《弈者》卡牌版 Godot 工程

当前实现、验证结果和剩余边界统一记录在 [可玩版本交接](docs/playable-handoff.md)。旧阶段交接与迁移评估保留作历史参考。

## 工程基准

- 工程根：本仓库根目录（当前为 `D:\游戏开发\弈者卡牌版`）。脚本会自行解析根目录，不依赖开发机用户名或固定盘符。
- Web 权威参考：`C:\Users\78566\Documents\ChatGPT\弈者-独立版\Html`；版本与只读边界见 [`docs/web-reference.md`](docs/web-reference.md)。
- 引擎版本：Godot 4.7.1 stable（GL Compatibility）
- 设计分辨率：1200 × 700；窗口保持 `canvas_items` 拉伸与 `expand` 宽高比策略。

不要把 Web 参考工程当作本工程的一部分或在其中写入。旧文档中的 `heliashi`、`新弈者` 和 `docs/migration-plan.md` 是历史环境/资料名，不是当前可执行路径。

## 当前入口与玩法闭环

运行入口是 [`scenes/run.tscn`](scenes/run.tscn)，`project.godot` 也指向该场景。它提供选人、三章地图、奖励、招募、商店、锻坊、部署和真实卡牌战斗的连续流程；战斗沿用 [`scenes/main.tscn`](scenes/main.tscn) 的既有表现栈，动画结束后才提交 Run 战果。

[`app/run_session.gd`](app/run_session.gd) 是 Run 的唯一组合入口。UI 只消费 `view_model()` / `snapshot()`，并通过 `execute(command)` 请求领域命令；不得直接改写 Run、牌堆或战斗状态。`catalog_snapshot()` 会提供英雄、自由技、遗物和专属技的展示字段。骑士的 `is_passive` 明确为真，界面应显示其被动说明，不应把它表述为一张主动专属卡。

节点之间自动保存到 `user://run-save.json`，包括 RNG、地图和待选权威选项。进入战斗前会先保存地图检查点；战斗中的开放进度不保存。暂停退出会恢复入战前检查点，战斗结算后才写入下一节点状态。若存档写入失败，`view_model().save_warning` 会给出提示，已提交的普通领域命令不会因此被重复执行。

Run 页面由 Godot 控件和脚本组合。棋子几何的当前参考是用户本轮提供的 [`tools/art/studies/geometry-crossbow-projectile.html`](tools/art/studies/geometry-crossbow-projectile.html) 右侧 `piece-geometry-v4.js`，已迁移为 [`ui/art/geometry_piece.gd`](ui/art/geometry_piece.gd) 的原生 `_draw`。角色继续显示 `assets/portraits/` 中已有立绘，并随可玩包导出；没有立绘的角色保留原文字占位。代码绘制的范围是棋子，不替换角色立绘。

M0–M5 的底层战斗、卡牌和肉鸽领域仍是当前基线。休眠神通不进入玩家流程；卡牌版数值平衡、真实三章胜率和批量稳定性仍需另行评估，不能由当前可玩入口推断完成。

## Windows 可运行交付

本机未安装 Godot 4.7.1 Windows export templates，因此交付使用可移植 main-pack：它把项目资源打包为 `YizheCardGame.pck`，再附带本机已有的 Godot Windows 引擎。它不是模板生成的独立 release，但在另一台 Windows 机器上不依赖本仓库、D 盘路径或 Godot 安装。

构建命令：

```powershell
& '.\tools\build_windows.ps1'
```

构建脚本依次使用 `-GodotExe`、`GODOT_BIN`、PATH 中的 `godot` / `godot4`，最后才尝试当前用户 Downloads 下的 Godot 4.7.1。新设备可显式指定引擎：

```powershell
& '.\tools\build_windows.ps1' -GodotExe 'C:\path\to\Godot_v4.7.1-stable_win64.exe'
# 或：$env:GODOT_BIN = 'C:\path\to\Godot_v4.7.1-stable_win64.exe'
```

产物在 `build\YizheCardGame\`。双击 `启动游戏.cmd` 即可调用同目录 `play.ps1`，后者以 `Godot.exe --main-pack YizheCardGame.pck` 启动游戏。运行日志写入 `build\YizheCardGame\logs\`，存档仍使用 Godot 的 `user://run-save.json`。交付前可执行 `& '.\build\YizheCardGame\play.ps1' -HeadlessSmoke` 检查 pack 是否能冷启动。

## 无头测试

全量发现入口是仓库内的统一 PowerShell 脚本。脚本会从自身位置解析工程根，因此不要求调用者当前位于工程目录；测试日志写入已被忽略的 `.godot/test-logs/`。

显式指定 Godot：

```powershell
& '.\tools\run_headless_tests.ps1' -GodotExe 'C:\path\to\godot_console.exe'
$LASTEXITCODE
```

也可以通过环境变量配置；没有显式参数和环境变量时，脚本依次查找 PATH 中的 `godot`、`godot4`：

```powershell
$env:GODOT_BIN = 'C:\path\to\godot_console.exe'
& '.\tools\run_headless_tests.ps1'
$LASTEXITCODE
```

`tests/run_all.gd` 会递归发现 `res://tests` 下的 `*_test.gd`，跳过名为 `support` 或 `fixtures` 的目录。每个 suite 只需实例化为对象并实现 `run(harness) -> void`，由 suite 调用 `harness.run_test(name, callable)` 注册用例。

Runner 的退出约定：全部通过为 0，发现/加载/断言失败为非 0。以下命令只用于验证失败出口，不会在正常发现路径留下故意失败 suite：

```powershell
& '.\tools\run_headless_tests.ps1' -GodotExe 'C:\path\to\godot_console.exe' -SelfTestFailure
$LASTEXITCODE
```

正常测试返回 0；`-SelfTestFailure` 映射为 runner 的 `-- --self-test-failure`，应返回 1。无效的显式路径、无效的 `GODOT_BIN` 或完全找不到 Godot 时，包装脚本在启动测试前返回 2。

日常默认验证不跑 1000 场稳定性套件，应直接运行 `run_regular_without_stability.gd` 或对应的聚焦 runner。所有 Godot 命令必须将日志写进工程：

```powershell
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\regular.log' --script res://tests/run_regular_without_stability.gd

# RunSession 聚焦验证
& 'C:\Users\78566\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'D:\游戏开发\弈者卡牌版' --log-file 'D:\游戏开发\弈者卡牌版\.godot\test-logs\run-session.log' --script res://tests/run_run_session.gd
```

将路径替换为本机实际位置。`tools/run_headless_tests.ps1` 运行 `tests/run_all.gd`，会递归发现包含历史 1000 场稳定性套件在内的全部测试，不是日常默认命令。它仍始终使用绝对工程根并显式传入 `--headless --log-file <工程内日志> --path <工程根>`。不要绕过它运行缺少 `--log-file` 的命令；Godot 默认写入 `user://logs` 在受限环境中可能导致原生崩溃。

需要历史 `m2_battle_stability_test.gd` 的 1000 场批量测试时应单独明确执行，并将其与 Run 的真实通关和数值平衡结论区分开。

## 分层与当前边界

依赖方向固定为 `data → core → systems → app → ui`。`core` 是不依赖 Node、场景或文件系统的纯逻辑；`systems` 组合纯逻辑系统；`app` 与 autoload 负责运行时装配和以后获准的 I/O；`ui`/场景只能消费 ViewModel 并发出 Command。

Autoload 仍限于 `Signals`、`GameRoot`、`RunState`、`HandManager`、`DebugLogger`，但它们不再只是 M0 边界壳：当前已承载 M3 卡牌会话和 M5 Run/战斗桥接的既有入口。新增功能仍须由相应里程碑冻结接口；特别是休眠神通不得绕过新的产品决策直接接入玩家流程。

## 日志与不变量

`DebugLogger` 只向内存和标准输出写入，severity 固定为 `info`、`warning`、`error`，不执行文件 I/O。日志记录是诊断信息，不代表操作成功。

程序员契约使用 `Invariant.require(condition, message)`：消息必须写清失败的约束和定位信息。调用方仍必须在返回 `false` 时立即停止当前操作；debug 构建中的 `assert` 用于尽早暴露缺陷，release 构建不能依赖 `assert` 承担控制流。

可恢复输入错误不属于程序员契约。接收输入的 API 必须在修改状态前校验，并通过明确的 `false`/空值等最小返回约定拒绝操作；调用方必须分支处理，不能只打印日志后继续。当前不引入通用 Result 框架。
