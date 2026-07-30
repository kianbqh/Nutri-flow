# NutriFlow 数据库看板与 iOS 测试指南

## 1. 当前数据边界

生产环境使用 MySQL，核心业务表目前只有两张：

| 表 | 用途 | 主要字段 |
| --- | --- | --- |
| `users` | 用户账号与健康目标 | 手机号、昵称、身高、体重、性别、饮食目标、每日热量目标、创建时间 |
| `diet_logs` | 餐食分析记录 | 用户 ID、任务 ID、餐次、图片对象键、分析结果 JSON、记录时间 |

截至 2026-07-30 的只读检查结果：

- 用户总数：9
- 提交过餐食的用户：7
- 餐食分析记录：11
- 已完成分析：11
- MySQL 中两张表合计约 3.6 MB

当前系统不保存设备 ID、设备指纹、IP、User-Agent 或独立的登录事件。因此，“新增用户数”按 `users.created_at` 统计，不能可靠地等同于“新增设备数”。不建议为了展示数据而静默加入设备指纹；如以后确实需要，应先增加隐私说明、保留期限和用户同意流程。

## 2. 安全查看数据库

数据库没有暴露到公网，这是正确的生产配置。推荐先 SSH 登录服务器，再通过 Docker 内的 MySQL 客户端只读查询。

### 2.1 登录服务器

在项目根目录的 PowerShell 中执行：

```powershell
ssh -i "..\.ssh\nutriflow-do-ed25519" `
  -o UserKnownHostsFile="..\.ssh\known_hosts" `
  root@157.230.38.184
```

登录后：

```bash
cd /opt/nutri-flow
docker compose --env-file .env.prod -f compose.prod.yml ps
```

### 2.2 进入 MySQL

下面的命令从容器环境变量读取账号和密码，不会把密码写入命令历史：

```bash
docker compose --env-file .env.prod -f compose.prod.yml exec mysql \
  sh -lc 'exec mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
```

常用只读 SQL：

```sql
SHOW TABLES;
DESCRIBE users;
DESCRIBE diet_logs;

SELECT COUNT(*) AS total_users FROM users;
SELECT COUNT(*) AS total_analyses FROM diet_logs;

SELECT
  id,
  CONCAT(LEFT(phone, 3), '****', RIGHT(phone, 4)) AS masked_phone,
  nickname,
  health_goal,
  daily_calorie_target,
  height_cm,
  weight_kg,
  gender,
  created_at
FROM users
ORDER BY created_at DESC
LIMIT 50;

SELECT
  DATE(created_at) AS day,
  COUNT(*) AS new_users
FROM users
GROUP BY DATE(created_at)
ORDER BY day DESC
LIMIT 30;

SELECT
  user_id,
  COUNT(*) AS analyses,
  MAX(logged_at) AS last_analysis_at
FROM diet_logs
GROUP BY user_id
ORDER BY last_analysis_at DESC;
```

退出 MySQL 使用 `exit`。不要在演示截图或公开文档中展示完整手机号、邮箱、密码哈希或完整 `analysis_result`。

### 2.3 图形化查看

可使用 DBeaver 的 SSH Tunnel：

1. SSH Host 填 `157.230.38.184`，用户填 `root`，私钥选择上级目录 `.ssh/nutriflow-do-ed25519`。
2. 在服务器执行 `docker inspect nutri-flow-mysql-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'` 获取 MySQL 容器 IP。
3. DBeaver 数据库 Host 填该容器 IP，Port 填 `3306`。
4. 数据库名、用户名和密码在服务器 `/opt/nutri-flow/.env.prod` 中查看，禁止把该文件提交到 Git。
5. 容器重建后 IP 可能变化，需要重新获取。

不要为了 DBeaver 把 MySQL 的 `3306` 端口直接映射到公网。

## 3. 数据看板

部署后访问：

```text
https://nutriflow.sunnxz.dev/dashboard
```

看板使用独立管理码，不复用公开测试站的访问授权码。管理码只保存在当前浏览器的 `sessionStorage`，关闭标签页后重新输入。本机管理码文件位于：

```text
G:\GraduationProj_Nutri-flow\Nutri-flow\.runtime\dashboard-admin-key.txt
```

看板只返回聚合数据：

- 用户总数、今日新增、近 7 日新增
- 提交过餐食的用户、近 7 日活跃用户
- 分析总数、今日分析、近 7 日分析、完成率
- 14 天新增用户和分析趋势
- 健康目标分布、餐次分布

看板还提供受保护的数据库记录板块：

- `users`：用户 ID、完整手机号、昵称、健康目标、每日热量目标、身高体重、性别、分析次数和注册时间
- `diet_logs`：记录 ID、用户 ID、完整手机号、任务 ID、餐次、状态、识别食物、总热量、建议生成状态和记录时间
- 两张表均使用服务端分页，单页默认 10 条
- 不返回密码哈希、验证码、邮箱、用户名、原始分析 JSON 或图片对象存储地址

聚合接口为 `GET /api/v1/admin/dashboard`，记录接口为
`GET /api/v1/admin/dashboard/records?table=users&page=0&size=10`。两者都要求
`X-Nutri-Admin-Key` 请求头并设置 `Cache-Control: no-store`。

## 4. 备份

在服务器中执行：

```bash
cd /opt/nutri-flow
mkdir -p backups
umask 077
docker compose --env-file .env.prod -f compose.prod.yml exec -T mysql \
  sh -lc 'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  > "backups/nutri_db_$(date +%Y%m%d_%H%M%S).sql"
ls -lh backups
```

下载到 G 盘：

```powershell
scp -i "..\.ssh\nutriflow-do-ed25519" `
  -o UserKnownHostsFile="..\.ssh\known_hosts" `
  "root@157.230.38.184:/opt/nutri-flow/backups/nutri_db_*.sql" `
  ".runtime\backups\"
```

备份含个人数据，不应提交到 Git 或分享给无关人员。

## 5. Web 与移动端同步范围

本轮已将下列 Web 行为同步到 Flutter：

| 能力 | Web | Flutter |
| --- | --- | --- |
| 站点授权码验证 | 已有 | 新增启动授权页，验证成功后直接进入应用 |
| 目标自然语言解析 | 结构化预览后保存 | 结构化预览后保存 |
| 性别未设置状态 | 不误判为女性 | 不误判为女性 |
| 低置信度识别 | 标记待确认 | 标记待确认，不进入具体建议 |
| 服务端错误信息 | 显示明确原因 | 显示明确原因 |
| 线上 API 地址 | 同域 `/api` | iOS 默认使用 `https://nutriflow.sunnxz.dev/api/v1` |

数据看板是管理功能，只提供 Web 版本，不应进入普通移动端用户导航。

## 6. 只有 iPhone 能否开发 iOS

不能只靠 iPhone 编译和签名 Flutter iOS 应用。Flutter 的 iOS 构建链依赖 macOS 与 Xcode；iPhone 可以安装和测试已经签名的构建，但不能替代 Xcode。依据：

- Flutter iOS 发布要求：[Build and release an iOS app](https://docs.flutter.dev/deployment/ios)
- Flutter iOS 开发环境：[Set up iOS development](https://docs.flutter.dev/get-started/install/macos/mobile-ios)

NutriFlow 当前 iOS 基线：

- Bundle ID：`dev.sunnxz.nutriflow`
- 最低 iOS：13.0
- 已声明相机、相册、麦克风和语音识别权限
- 已配置 App 图标资源

## 7. 推荐的无 Mac 测试路线

最适合当前条件的是“Windows 开发 + GitHub Actions macOS 构建 + TestFlight 安装到 iPhone”。

### 7.1 Apple 侧准备

1. 注册 Apple ID。
2. 加入 [Apple Developer Program](https://developer.apple.com/programs/whats-included/)。正式 TestFlight 和 App Store 分发通常需要付费会员，官方标准费用为每年 99 美元或当地等值价格。
3. 进入 [App Store Connect](https://developer.apple.com/app-store-connect/) 创建应用：
   - Name：NutriFlow
   - Primary Language：Simplified Chinese
   - Bundle ID：`dev.sunnxz.nutriflow`
   - SKU：可用 `nutriflow-ios`
4. 在 Certificates, Identifiers & Profiles 中注册相同 Bundle ID。
5. 创建 Apple Distribution 证书和 App Store Provisioning Profile。
6. 在 App Store Connect 的 Users and Access 中创建 API Key，并记录 Issuer ID、Key ID，下载一次性的 `.p8` 私钥。

### 7.2 GitHub Actions 机密

在 GitHub 仓库 `Settings > Secrets and variables > Actions` 中准备：

| Secret | 内容 |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `.p8` 文件全文 |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | `.p12` 证书的 Base64 |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 Base64 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码 |

这些值不能写进仓库、Issue、聊天截图或应用代码。GitHub 提供 macOS 托管 Runner，详情见 [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

### 7.3 构建与上传流程

准备好上述资料后，再加入 iOS 发布工作流。工作流应执行：

1. Checkout 代码。
2. 安装项目指定 Flutter 版本。
3. 在 `nutri-mobile` 执行 `flutter pub get`。
4. 导入签名证书和 Provisioning Profile。
5. 执行 `flutter analyze` 与 `flutter test`。
6. 执行 `flutter build ipa --release --build-number <递增编号>`。
7. 使用 App Store Connect API Key 上传 `.ipa`。
8. 在 App Store Connect 等待构建处理完成。

Apple 的上传说明：[Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)。

### 7.4 在 iPhone 上测试

1. 从 App Store 安装 TestFlight。
2. 在 App Store Connect 的 TestFlight 页面选择刚上传的构建。
3. 先把自己的 Apple ID 加入 Internal Testing。
4. 接受邀请，在 iPhone 的 TestFlight 中安装 NutriFlow。
5. 首次启动依次验证：
   - 输入站点授权码后直接进入应用
   - 手机号登录或注册
   - 相机和相册权限
   - 上传餐食并获得识别结果
   - 低置信度食物提示
   - 目标文字解析、应用并保存
   - 语音输入及麦克风、语音识别权限
   - 退出登录和重新登录
6. 每次发布递增 `pubspec.yaml` 中的 build number，例如 `1.0.0+2`。

TestFlight 官方说明：[TestFlight](https://developer.apple.com/testflight/)。外部测试者需要创建测试组，首个构建通常还要经过 Beta App Review，流程见 [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)。

### 7.5 免费账号的限制

免费 Apple ID 也能在连接 Xcode 的真机上临时测试，但仍然需要 Mac/Xcode，而且签名有效期和可注册能力受限，因此不适合当前“只有 Windows 与 iPhone”的条件。当前阶段可以继续在 Windows 做 Flutter 静态检查、Web 和 Android 测试；准备好 Apple 开发者账号资料后，再一次性接通 GitHub Actions 与 TestFlight。

## 8. 发布前检查

- 不在 Flutter 包中硬编码生产授权码或 Apple 密钥
- 后端 API 全部使用 HTTPS
- 更新隐私政策，说明账号、健康目标、餐食图片和分析结果的用途
- App Store 隐私问卷与实际采集字段一致
- 提供账号删除或数据删除入口后再公开发布
- 对相机、相册、麦克风、语音识别逐项做真机拒绝权限测试
- 为数据库建立定时备份与恢复演练
