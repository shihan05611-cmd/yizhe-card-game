# 《弈者》卡牌版 Godot 工程

## 工程基准

- 唯一工程根：`C:/Users/heliashi/Documents/弈者卡牌版/弈者卡牌Godot/弈者卡牌版`
- 引擎版本：Godot 4.7.1 stable（GL Compatibility）
- 设计分辨率：1200 × 700；窗口保持 `canvas_items` 拉伸与 `expand` 宽高比策略。

不要从上层 `弈者卡牌Godot` 目录启动，也不要把 Web 工程或 STR 参考工程当作本工程的一部分。

## 无头测试

首选使用仓库内的统一 PowerShell 入口。脚本会从自身位置解析工程根，因此不要求调用者当前位于工程目录；测试日志写入已被忽略的 `.godot/test-logs/`。

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

包装脚本底层始终使用绝对工程根并显式传入 `--headless --log-file <工程内日志> --path <工程根> --script res://tests/run_all.gd`。不要绕过包装脚本运行缺少 `--log-file` 的命令；Godot 默认写入 `user://logs` 在受限环境中可能导致原生崩溃。

## 分层与当前边界

依赖方向固定为 `data → core → systems → app → ui`。`core` 是不依赖 Node、场景或文件系统的纯逻辑；`systems` 组合纯逻辑系统；`app` 与 autoload 负责运行时装配和以后获准的 I/O；`ui`/场景只能消费 ViewModel 并发出 Command。

M0 只注册五个 autoload：`Signals`、`GameRoot`、`RunState`、`HandManager`、`DebugLogger`。前四者目前只是可解析的边界壳，不能据此推断卡牌、战斗、肉鸽、存档或 UI API；`Signals` 仅有基础生命周期信号。后续业务接口必须由对应里程碑单独冻结。

## 日志与不变量

`DebugLogger` 只向内存和标准输出写入，severity 固定为 `info`、`warning`、`error`，不执行文件 I/O。日志记录是诊断信息，不代表操作成功。

程序员契约使用 `Invariant.require(condition, message)`：消息必须写清失败的约束和定位信息。调用方仍必须在返回 `false` 时立即停止当前操作；debug 构建中的 `assert` 用于尽早暴露缺陷，release 构建不能依赖 `assert` 承担控制流。

可恢复输入错误不属于程序员契约。接收输入的 API 必须在修改状态前校验，并通过明确的 `false`/空值等最小返回约定拒绝操作；调用方必须分支处理，不能只打印日志后继续。当前不引入通用 Result 框架。
