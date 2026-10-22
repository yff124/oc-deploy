# =============================================================
#  OpenClaw 一键部署工具（Windows 版） v1.0
#  用法：右键"使用 PowerShell 运行"
#  如提示脚本被禁止，先执行：
#    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# =============================================================

$ErrorActionPreference = "Continue"
$PortDefault = 18789

function Write-Ok   ($m){ Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn ($m){ Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Write-Err  ($m){ Write-Host "  [X]  $m" -ForegroundColor Red }
function Write-Info ($m){ Write-Host "  [.]  $m" -ForegroundColor Cyan }
function Write-Step ($n,$m){ Write-Host "`n[$n] $m" -ForegroundColor Cyan }

Write-Host @"

   OpenClaw 一键部署工具  v1.0  (Windows)
   已实测验证 · 自动绕过 6 个已知卡点

"@ -ForegroundColor Magenta

# --------- 卡点1：Node 版本（网上教程大多写错成 18+） ---------
Write-Step "1/6" "检查 Node.js 运行环境"

function Test-NodeVersion {
    try {
        $v = (& node -v 2>$null)
        if (-not $v) { return $false }
        $v = $v.TrimStart('v')
        $parts = $v.Split('.')
        $major = [int]$parts[0]; $minor = [int]$parts[1]
        if ($major -eq 24 -and $minor -ge 22) { return $true }
        if ($major -eq 26 -and $minor -ge 12) { return $true }
        if ($major -gt 26) { return $true }
        return $false
    } catch { return $false }
}

$hasNode = (Get-Command node -ErrorAction SilentlyContinue) -ne $null
$curVer = if ($hasNode) { (& node -v) } else { "(未安装)" }

if ($hasNode -and (Test-NodeVersion)) {
    Write-Ok "Node $curVer 符合要求"
    Write-Host "      要求：24.22.1+ 或 26.12.1+（多数教程写 18+，是错的）" -ForegroundColor DarkGray
} else {
    Write-Warn "当前 Node $curVer 不符合要求"
    Write-Host "      OpenClaw 要求 24.22.1+ 或 26.12.1+" -ForegroundColor DarkGray
    Write-Host "`n  正在用官方安装器安装（会自动装 Node）..." -ForegroundColor Cyan
    try {
        iwr -useb https://openclaw.ai/install.ps1 | iex
    } catch {
        Write-Err "官方安装器执行失败"
        Write-Host @"

  请手动安装 Node 26：
    1. 打开 https://nodejs.org
    2. 下载 Node 26 (LTS) 的 Windows 安装包 (.msi)
    3. 一路下一步安装完成
    4. 关掉这个窗口，重新运行本脚本

"@ -ForegroundColor Yellow
        Read-Host "按回车退出"
        exit 1
    }
    # 刷新环境变量
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Test-NodeVersion)) {
        Write-Err "安装后版本仍不符合要求，请手动安装 Node 26 后重试"
        Read-Host "按回车退出"; exit 1
    }
    Write-Ok "Node 已就绪：$(& node -v)"
}

# --------- 卡点3：npm 脚本授权（必须一次性给全 5 个包） ---------
Write-Step "2/6" "安装 OpenClaw"

$ocCmd = Get-Command openclaw -ErrorAction SilentlyContinue
if ($ocCmd) {
    $ocVer = (& openclaw --version 2>$null | Select-Object -First 1)
    Write-Ok "已安装：$ocVer"
} else {
    $npmv = (& npm -v 2>$null)
    Write-Info "npm 版本：$npmv"
    Write-Host "      关键：必须一次性授权 5 个包，否则会漏装原生依赖" -ForegroundColor DarkGray
    Write-Info "正在安装（约 15–60 秒）..."

    $allow = "openclaw,@google/genai,esbuild,koffi,protobufjs"
    & npm install -g --allow-scripts=$allow openclaw@latest 2>&1 | Tee-Object -Variable npmOut | Out-Null

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    $ocCmd = Get-Command openclaw -ErrorAction SilentlyContinue

    if ($ocCmd) {
        Write-Ok "安装成功：$(& openclaw --version 2>$null | Select-Object -First 1)"
        Write-Host "      出现 TAR_ENTRY_ERROR 警告是正常的，可忽略" -ForegroundColor DarkGray
    } else {
        Write-Err "安装失败"
        Write-Host @"

  请依次尝试：
    1. 用管理员身份打开 PowerShell，重新运行
    2. npm cache clean --force
    3. npm install -g --allow-scripts=openclaw,@google/genai,esbuild,koffi,protobufjs openclaw@latest

"@ -ForegroundColor Yellow
        Read-Host "按回车退出"; exit 1
    }
}

# --------- 卡点4：gateway.mode 未设置会拒绝启动 ---------
Write-Step "3/6" "配置 Gateway"
& openclaw config set gateway.mode local 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Ok "gateway.mode = local" } else { Write-Warn "配置写入失败" }

# 令牌：openclaw config get 会显示 REDACTED，需直接读配置文件
$cfgPath = Join-Path $HOME ".openclaw\openclaw.json"
$hasToken = $false
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.gateway.auth.token -and $cfg.gateway.auth.token.Length -gt 0) { $hasToken = $true }
    } catch {}
}
if ($hasToken) {
    Write-Ok "访问令牌已就绪"
} else {
    Write-Info "生成访问令牌..."
    & openclaw doctor --fix --generate-gateway-token 2>&1 | Out-Null
    if (Test-Path $cfgPath) { Write-Ok "令牌已生成" } else { Write-Warn "令牌未生成，首次打开控制台时按提示创建" }
}

# --------- 卡点5：服务启动 ---------
Write-Step "4/6" "启动 Gateway"

function Test-Health {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$PortDefault/health" -TimeoutSec 3 -UseBasicParsing
        return $r.Content -match '"ok":true'
    } catch { return $false }
}

if (Test-Health) {
    Write-Ok "Gateway 已在运行（端口 $PortDefault）"
} else {
    Write-Info "尝试作为 Windows 服务启动..."
    & openclaw gateway start 2>&1 | Out-Null
    Start-Sleep -Seconds 5
    if (-not (Test-Health)) {
        Write-Warn "服务方式未成功，改用后台进程启动"
        Start-Process -FilePath "openclaw" -ArgumentList "gateway","run" -WindowStyle Hidden `
            -RedirectStandardOutput "$HOME\.openclaw-gateway.log" `
            -RedirectStandardError "$HOME\.openclaw-gateway.err.log"
        Write-Info "等待启动（最多 40 秒）..."
        $started = $false
        for ($i=0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 2
            if (Test-Health) { $started = $true; break }
        }
        if (-not $started) {
            Write-Err "启动超时，日志：$HOME\.openclaw-gateway.log"
            Read-Host "按回车退出"; exit 1
        }
        Write-Ok "Gateway 启动成功"
    } else {
        Write-Ok "Gateway 已作为服务启动"
    }
}

# --------- 卡点6：装完不知道下一步 ---------
Write-Step "5/6" "健康检查"
try {
    $h = (Invoke-WebRequest -Uri "http://127.0.0.1:$PortDefault/health" -TimeoutSec 5 -UseBasicParsing).Content
    Write-Ok "服务健康：$h"
} catch {
    Write-Err "健康检查未通过"
    Read-Host "按回车退出"; exit 1
}
try {
    $code = (Invoke-WebRequest -Uri "http://127.0.0.1:$PortDefault/" -TimeoutSec 5 -UseBasicParsing).StatusCode
    if ($code -eq 200) { Write-Ok "控制台可访问（HTTP 200）" }
} catch { Write-Warn "控制台访问异常" }

Write-Step "6/6" "完成"

# 读取令牌用于展示
$token = ""
if (Test-Path $cfgPath) {
    try { $token = (Get-Content $cfgPath -Raw | ConvertFrom-Json).gateway.auth.token } catch {}
}

Write-Host @"

  ================================================
   部署完成
  ================================================

   控制台地址：  http://127.0.0.1:$PortDefault
   访问令牌：    $token

   下一步（必做）：
     1. 配置模型 API —— 运行  openclaw configure
        国产模型更便宜稳定，推荐 deepseek / qwen
     2. 浏览器打开上面的地址，粘贴令牌
     3. 发一条消息，确认助手能回复

   常用命令：
     查看状态：  openclaw gateway status
     查看令牌：  openclaw config get gateway.auth
     打开面板：  openclaw dashboard
     自检排错：  openclaw doctor

"@ -ForegroundColor Green

Write-Host "  按回车打开控制台..." -ForegroundColor Cyan
Read-Host | Out-Null
Start-Process "http://127.0.0.1:$PortDefault"
