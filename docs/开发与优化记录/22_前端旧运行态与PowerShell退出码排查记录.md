# 22 前端旧运行态与 PowerShell 退出码排查记录

## 1. 文档目的

本记录用于解释两个联调阶段容易混淆的问题：

1. 为什么会弹出“PowerShell 进程已终止，退出代码 2”的提示。
2. 为什么只有在整条链路重启之后，用户才真正看到了优化后的分割图像。

同时，本记录也沉淀了本次为避免问题再次出现而增加的工程化措施。

## 2. 现象总结

本轮联调中出现了两个表面上独立、实际上互相关联的现象：

1. VS Code 弹出 PowerShell 终端进程终止提示，退出代码为 2。
2. 用户在多次局部调整结果页代码后，页面视觉效果始终没有明显变化；直到整条链路重启后，才看到优化后的分割图像。

## 3. 原因拆解

### 3.1 退出代码 2 不是后端链路崩溃

排查脚本后确认，仓库中的 `dev-up.ps1`、`dev-down.ps1`、`dev-health.ps1` 并没有主动使用 `exit 2` 作为业务状态码。

因此，这个提示不是 inference、business 或 agent 链路自身的约定错误码，而更像是“辅助终端壳层异常退出”的现象。

### 3.2 根因在于前端调试实例是通过临时 PowerShell 终端反复拉起的

此前前端 web 调试实例主要依赖临时命令：

1. 在集成终端中执行 `flutter run -d web-server --web-port 57717`
2. 为了清理旧实例，又会在同类终端中执行停止端口占用、杀进程、重新运行等动作

这会带来两个问题：

1. 同一台机器上可能存在多个先后启动的 Flutter web-server 包。
2. 当旧的包装 PowerShell / cmd / dart 链被强制停止时，VS Code 会把壳层终止显示为一个终端退出提示，表现为 PowerShell 非零退出码。

也就是说，弹窗里的退出码更多反映的是“辅助终端被终止”，而不是“整条产品链路崩溃”。

### 3.3 只有整链路重启后才看到新分割图，是因为旧前端运行态终于被清干净了

之前之所以“代码明明改了，页面却几乎没变”，高概率原因并不是代码没有写进仓库，而是：

1. 浏览器仍然访问着旧的 Flutter web 调试实例。
2. 旧调试实例继续服务旧 bundle。
3. 用户截图实际上来自旧前端运行态，而不是最新结果页代码。

整链路重启之后，旧前端调试实例被一并清理，浏览器重新连到新实例，优化后的分割图才终于可见。

## 4. 关键证据

### 4.1 代码逻辑与截图表现不一致

结果页当前代码中：

1. `_selectedGroup` 只在点击命中时才赋值。
2. 页面默认不会直接展示分类详情卡。
3. 新版页面还增加了“轻量轮廓模式”等显式 UI 标记。

如果实际截图仍然表现为“默认已选中 + 旧徽标样式 + 无新标记”，那么该截图就不能来自最新代码。

### 4.2 当前 Flutter web 运行形态存在多层包装进程

进程树显示前端 web-server 运行时通常包含：

1. PowerShell 终端壳层
2. `cmd.exe /c flutter.bat run ...`
3. `dart.exe / dartvm.exe`

因此，一旦中途停止包装层、抢占端口或重复启动，就容易出现“壳层退出提示”和“旧实例仍在服务”的混合问题。

## 5. 为避免重蹈覆辙所做的工程化修正

### 5.1 给 Flutter web 前端增加受管启动脚本

新增：

1. `scripts/frontend-web-up.ps1`
2. `scripts/frontend-web-down.ps1`

作用：

1. 把 Flutter web-server 纳入和后端一致的受管启动方式。
2. 使用 `.runtime/pids/`、`.runtime/logs/`、`.runtime/supervisors/` 保存 PID、日志和 supervisor 脚本。
3. 避免继续依赖临时 PowerShell 终端反复手工执行 `flutter run`。

### 5.2 提供统一的全链路重启脚本

新增：

1. `scripts/dev-restart-all.ps1`

作用：

1. 先停前端，再停后端。
2. 再启动后端并健康检查。
3. 最后启动前端 web-server。

这样后续若需要“整链路重启再测试”，不必再手工组合多条命令。

## 6. 建议使用方式

后续本地联调尽量使用以下脚本，而不要再手工反复执行临时命令：

1. 启动前端：`powershell -ExecutionPolicy Bypass -File scripts/frontend-web-up.ps1`
2. 停止前端：`powershell -ExecutionPolicy Bypass -File scripts/frontend-web-down.ps1`
3. 全链路重启：`powershell -ExecutionPolicy Bypass -File scripts/dev-restart-all.ps1`

## 6.1 本轮验证结果

在修复 `frontend-web-down.ps1` 中的 PowerShell 字符串转义问题后，前端受管脚本已经完成验证：

1. `frontend-web-down.ps1` 可以正常停止前端 web-server 并释放 57717 端口。
2. `frontend-web-up.ps1` 可以重新启动受管的 Flutter web-server，并写入 `.runtime/pids/frontend-web.pid` 与对应日志。
3. 当前前端实例已不再依赖临时手工终端，而是由 `.runtime/supervisors/frontend-web.ps1` 受管启动。

## 7. 工程结论

本次问题的本质不是某个后端服务持续崩溃，而是“前端调试实例缺少统一管理”，导致：

1. 旧 bundle 与新 bundle 交替存在。
2. 壳层终端退出提示干扰判断。
3. 用户看到的页面效果和仓库当前代码不一致。

通过把 Flutter web 前端也纳入受管脚本体系，可以显著降低这类联调误判再次发生的概率。