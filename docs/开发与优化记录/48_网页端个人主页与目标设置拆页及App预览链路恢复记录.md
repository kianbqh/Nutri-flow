# 48_网页端个人主页与目标设置拆页及App预览链路恢复记录

## 1. 背景

在移动端完成“个人主页 / 目标设置”拆页后，网页端仍保留着旧的合并式结构，导致两个问题同时出现：

1. 网页端的账号昵称维护、目标设置、助手解析还混在一个入口里，和 app 端的使用路径不一致。
2. 用户反馈 app 端预览偶发掉线，需要确认究竟是业务后端异常，还是本地预览链路自身不稳定。

本轮工作的目标因此分成两部分：

1. 将网页端同步为“个人主页”和“目标设置”双页面结构，并沿用移动端已经验证过的昵称编辑模式。
2. 找出 app 端掉线的实际链路与根因，恢复当前可测试状态，并形成后续可复用的排查结论。

## 2. 问题定位

### 2.1 网页端信息结构仍停留在合并页

问题主要集中在以下文件：

1. nutri-web/src/views/ProfileView.vue
2. nutri-web/src/App.vue
3. nutri-web/src/router/index.js
4. nutri-web/src/views/HomeView.vue
5. nutri-web/src/api/dietLog.js

此前网页端虽然已经补了账号绑定与昵称能力，但页面仍然承担了过多职责，用户进入后既要判断账号状态，又要填写目标和饮食限制，主次不够明确。

### 2.2 app 掉线并非业务服务异常

排查过程中对 4173、57717、6006、8001、8080 的运行态分别做了检查，业务后端与 TensorBoard 并未出现统一掉线现象。真正异常的是 Flutter web 预览链路。

在前端预览日志中可以稳定看到以下特征：

1. frontend-web-supervisor 持续检测到 flutter run 退出并反复重启。
2. 日志中出现 FileSystemException: writeFrom failed。
3. 失败文件位于 C:\Users\Sunnxz\AppData\Local\Temp\flutter_tools* 目录下的 app.dill。
4. 错误号为 errno = 112，对应磁盘空间不足。

进一步清理 Windows 临时目录后，可用空间由约 0.08GB 恢复到约 3.91GB，说明这次掉线的根因不是推理服务、业务服务或 RabbitMQ，而是本地 Flutter 编译缓存写入失败。

## 3. 本次修改

### 3.1 网页端拆分为个人主页与目标设置页

处理文件：

1. nutri-web/src/views/ProfileView.vue
2. nutri-web/src/views/GoalSettingsView.vue
3. nutri-web/src/router/index.js
4. nutri-web/src/App.vue
5. nutri-web/src/views/HomeView.vue

处理内容：

1. 将网页端个人空间拆为 /profile 和 /goals 两个独立页面。
2. 个人主页只负责手机号验证、昵称展示与修改、当前设置概览。
3. 目标设置页独立承接助手输入、基础信息、健康目标、热量与饮食限制维护。
4. 顶部导航和首页入口同步调整，统一成与移动端一致的访问路径。

### 3.2 网页端昵称修改交互同步到主流显式编辑模式

处理文件：nutri-web/src/views/ProfileView.vue

处理内容：

1. 删除默认昵称建议思路，改为显示态 / 编辑态切换。
2. 用户主动点击修改昵称后，才展示输入框与保存按钮。
3. 昵称和目标设置彻底分离，避免一个页面承担两种不同任务。

### 3.3 上传页与历史页入口语义同步收口

处理文件：

1. nutri-web/src/views/UploadView.vue
2. nutri-web/src/views/HistoryView.vue

处理内容：

1. 将“去个人资料页验证”统一改为“去个人主页验证”。
2. 将“个人资料”描述统一改成“个人主页资料”，避免拆页后仍残留旧概念。

### 3.4 恢复 Flutter web 预览链路

处理内容：

1. 清理 C:\Users\Sunnxz\AppData\Local\Temp 下的 flutter_tools 临时目录。
2. 重新拉起 57717 对应的 Flutter web 预览链路。
3. 复查端口监听状态，确认页面已恢复可访问。

## 4. 验证

执行与确认内容：

1. 在 nutri-web 下执行 npm run build，构建通过。
2. 浏览器实际检查 4173/profile 与 4173/goals，两页均已切换为拆页后的结构。
3. 复查 57717 端口监听状态，确认 Flutter web 预览恢复正常。
4. 同步确认 6006、8001、8080 仍然可用，排除误判为全链路掉线。

验证结论：

1. 网页端拆页结构已经落地，入口、导航和页面职责一致。
2. app 端本轮“掉线”本质上是本地 Flutter 预览编译缓存写入失败，不是服务端链路中断。
3. 清理临时目录并重启预览后，当前测试链路已恢复。

## 5. 结果

本轮处理后，网页端和移动端的个人空间结构已经基本对齐：

1. 个人主页专注于账号身份与昵称维护。
2. 目标设置页专注于健康目标、基础信息和限制条件配置。
3. 上传页、历史页等依赖账号验证的入口，已经统一指向“个人主页”。
4. 后续若再出现 57717 预览反复掉线，应优先检查 Windows 临时目录空间，而不是先怀疑业务后端异常。