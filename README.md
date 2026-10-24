# OpenClaw 一键部署

> 已实测跑通：Node 26.12.1 / OpenClaw 2026.10.6 / Linux
> 自动绕过 6 个官方文档没写、网上教程写错的问题。

---

## 一条命令部署（Linux / macOS）

```bash
{ curl -fsSL --max-time 20 https://cdn.jsdelivr.net/gh/yff124/oc-deploy@main/scripts/deploy.sh \
  || curl -fsSL --max-time 30 https://raw.githubusercontent.com/yff124/oc-deploy/main/scripts/deploy.sh; } | bash
```

复制这一整段（含大括号）粘进终端回车就行。它会**自动选快的通道**：先走 jsDelivr CDN（国内实测 0.7 秒），
连不上再自动换 GitHub 直连。

### Windows（PowerShell 管理员）

```powershell
$u=@("https://cdn.jsdelivr.net/gh/yff124/oc-deploy@main/scripts/deploy.ps1","https://raw.githubusercontent.com/yff124/oc-deploy/main/scripts/deploy.ps1")
foreach($x in $u){ try{ iwr -useb $x -OutFile "$env:TEMP\deploy.ps1"; break }catch{} }
powershell -ExecutionPolicy Bypass -File "$env:TEMP\deploy.ps1"
```

### 只有单通道能用时

```bash
# 只走 CDN
curl -fsSL https://cdn.jsdelivr.net/gh/yff124/oc-deploy@main/scripts/deploy.sh | bash

# 只走 GitHub
curl -fsSL https://raw.githubusercontent.com/yff124/oc-deploy/main/scripts/deploy.sh | bash
```

> ⚠️ **超时值很关键**：实测网络波动时 `--max-time 8` 会被误判成"下载失败"，
> 所以上面都用 20/30 秒，别改成更小的值。

### 如果两条通道都失败

说明网络限制较严。用最稳的方式——**手动下文件再跑**：

```bash
# 方式A：浏览器打开链接，右键另存为 deploy.sh，然后
bash deploy.sh

# 方式B：用 wget 代替 curl
wget -qO- https://cdn.jsdelivr.net/gh/yff124/oc-deploy@main/scripts/deploy.sh | bash
```

> 上面用的是我自己的仓库 `yff124/oc-deploy`。你要是 fork 了自己用，把 `yff124` 换成你的用户名就行。

---

## 它做了什么

| 步骤 | 说明 |
|---|---|
| 1. 检查 Node | 自动识别版本是否满足 **24.22.1+ / 26.12.1+**（不是网上说的 18+） |
| 2. 安装 OpenClaw | 一次性给全 5 个依赖授权，避免原生模块缺失 |
| 3. 配置 Gateway | 自动设置 `gateway.mode=local` 并生成访问令牌 |
| 4. 启动服务 | 有 systemd 用服务方式，容器/无 systemd 自动降级为后台进程 |
| 5. 健康检查 | 验证 `/health` 返回 `{"ok":true}` 和控制台 HTTP 200 |
| 6. 输出结果 | 打印访问地址、令牌、下一步指引 |

---

## 它替你避开的 6 个坑

| # | 问题 | 网上怎么说 | 真实情况 |
|---|---|---|---|
| 1 | **Node 版本** | "Node 18+" | 必须 **24.22.1+ 或 26.12.1+**，**25.x 不兼容** |
| 2 | **nvm 拦截** | 无人提及 | 装了 nvm 时官方安装器**会直接中止**，不会自动升级 |
| 3 | **npm 脚本授权** | 无人提及 | 必须一次性授权 5 个包，只给 1 个或 4 个都会漏装 |
| 4 | **TAR_ENTRY_ERROR** | 无人提及 | 这是**正常警告**，不代表失败，很多人误判放弃 |
| 5 | **无 systemd** | 无人提及 | 容器/云服务器 `gateway start` 会失败，须用 `gateway run` |
| 6 | **令牌打码** | 无人提及 | `config get` 显示 `__OPENCLAW_REDACTED__` 是**正常**的 |

**端口**：真实是 **18789**。网上流传的 8080、3000 都是错的。

---

## 常用命令

```bash
# 部署后你可以这样管理
bash deploy.sh --check     # 只检查环境，不安装
bash deploy.sh --status    # 查看运行状态
bash deploy.sh --token     # 查看控制台访问令牌
bash deploy.sh --report    # 生成排错报告（出问题时用）
bash deploy.sh --stop      # 停止服务
```

> 用 `curl | bash` 方式安装的，可先把脚本保存到本地再使用这些命令：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/yff124/oc-deploy/main/scripts/deploy.sh -o deploy.sh
> bash deploy.sh --token
> ```

---

## 部署完之后

```bash
openclaw configure      # 配置模型 API（推荐 deepseek / qwen，便宜稳定）
openclaw dashboard      # 打开控制台
openclaw doctor         # 出任何问题先跑这个
```

1. 浏览器打开 `http://127.0.0.1:18789`
2. 粘贴令牌登录
3. 发一条消息，确认助手能回复

---

## 常见问题

**Q：提示 Node 版本不符合怎么办？**
A：脚本会自动尝试升级。如果失败，手动装 Node 26：
```bash
nvm install 26 && nvm use 26 && nvm alias default 26
```
没有 nvm 就去 https://nodejs.org 下载 Node 26 安装包。

**Q：安装时一堆红色 warning？**
A：`TAR_ENTRY_ERROR` 属于正常警告。判断成功的唯一标准是最后能打印版本号。

**Q：启动失败？**
A：容器/云服务器没有 systemd 是正常现象，脚本会自动改用后台进程。手动方式：
```bash
nohup openclaw gateway run > ~/.openclaw-gateway.log 2>&1 &
```

**Q：控制台要令牌，但查出来是 `__OPENCLAW_REDACTED__`？**
A：这是安全打码，令牌是好的。用 `bash deploy.sh --token` 读取。

更多排错见 [docs/部署排错手册.md](docs/部署排错手册.md)。

---

## 安全说明

- 本脚本只做三件事：检查环境、安装 OpenClaw、启动服务。
- **不改动系统配置**，不写注册表，不收集任何数据。
- 令牌保存在本机 `~/.openclaw/openclaw.json`，不会外传。
- 脚本内容完全公开，可自行审阅。

---

## 说明

本仓库提供的是**部署自动化脚本**，OpenClaw 本身是 [OpenClaw Foundation](https://openclaw.org) 的开源项目（MIT 协议）。
本脚本与其无隶属关系，仅做安装流程封装。

如遇问题，请先运行 `bash deploy.sh --report` 并把输出发给服务提供者。
