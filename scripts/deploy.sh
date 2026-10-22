#!/usr/bin/env bash
# =============================================================
#  OpenClaw 一键部署工具  v1.0
#  作者：实测跑通全链路（Node 26.12.1 / OpenClaw 2026.10.6 验证）
#  作用：把"装不上"这件事彻底解决 —— 自动处理 6 个真实卡点
# =============================================================
set -uo pipefail

VER="1.0"
OC_MIN_NODE_MAJOR=24
OC_MIN_NODE_MINOR=22
OC_ALT_NODE_MAJOR=26
OC_ALT_NODE_MINOR=12
PORT_DEFAULT=18789

C_RESET='\033[0m'; C_G='\033[32m'; C_Y='\033[33m'; C_R='\033[31m'; C_B='\033[36m'; C_D='\033[2m'
ok(){   printf "${C_G}✓${C_RESET} %s\n" "$*"; }
warn(){ printf "${C_Y}!${C_RESET} %s\n" "$*"; }
err(){  printf "${C_R}✗${C_RESET} %s\n" "$*"; }
info(){ printf "${C_B}·${C_RESET} %s\n" "$*"; }
step(){ printf "\n${C_B}[%s]${C_RESET} %s\n" "$1" "$2"; }
dim(){  printf "${C_D}  %s${C_RESET}\n" "$*"; }

LOG="$HOME/.openclaw-deploy-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

banner(){
cat <<'EOF'

   ___                  ____ _
  / _ \ _ __   ___ _ __/ ___| | __ ___      __
 | | | | '_ \ / _ \ '_ \___ \ |/ _` \ \ /\ / /
 | |_| | | | |  __/ | | |__) | | (_| |\ V  V /
  \___/|_| |_|\___|_| |_|____/|_|\__,_| \_/\_/

  OpenClaw 一键部署工具  v1.0
  已实测验证 · 自动绕过 6 个已知卡点

EOF
}

# --------- 卡点1：Node 版本识别（网上教程大多写错） ---------
node_ok(){
  local v major minor patch
  v="$(node -v 2>/dev/null)" || return 1
  v="${v#v}"; major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
  # 要求：>=24.22.1 且 <25  或  >=26.12.1
  if [ "$major" -eq 24 ] && [ "$minor" -ge "$OC_MIN_NODE_MINOR" ]; then return 0; fi
  if [ "$major" -eq 26 ] && [ "$minor" -ge "$OC_ALT_NODE_MINOR" ]; then return 0; fi
  if [ "$major" -gt 26 ]; then return 0; fi
  return 1
}

ensure_node(){
  step "1/6" "检查 Node.js 运行环境"
  local cur="(未安装)"
  command -v node >/dev/null 2>&1 && cur="$(node -v)"

  if node_ok; then
    ok "Node $cur 符合要求"
    dim "要求：24.22.1+ 或 26.12.1+（多数教程写 18+，是错的）"
    return 0
  fi

  warn "当前 Node $cur 不符合要求"
  dim "OpenClaw 要求 24.22.1+ 或 26.12.1+"
  dim "原因：旧版 node:sqlite 会截断文本（nodejs/node#61954）"

  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # --------- 卡点2：装了 nvm 时官方安装器会直接中止 ---------
    info "检测到 nvm —— 官方安装器遇到 nvm 会中止，这里帮你自动切换"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    if ! nvm which 26 >/dev/null 2>&1; then
      info "正在安装 Node 26（约 30–60 秒，请稍候）..."
      nvm install 26 || { err "Node 安装失败，请检查网络"; return 1; }
    fi
    nvm use 26 >/dev/null 2>&1
    nvm alias default 26 >/dev/null 2>&1
    if node_ok; then
      ok "已切换到 Node $(node -v)"
      dim "已设为默认版本，新开终端也生效"
      return 0
    fi
    err "切换后版本仍不符合要求：$(node -v 2>/dev/null)"
    return 1
  fi

  # 没有 nvm：自动安装官方安装器（它会自带 Node）
  info "未检测到 nvm，改用官方安装器（会自动装 Node）"
  info "正在下载并执行官方安装器，可能需要 1–3 分钟..."
  dim "如自动安装失败，会给出手动步骤"

  if command -v curl >/dev/null 2>&1; then
    # 官方安装器若检测到现有不兼容 Node，可能中止；先尝试，失败再兜底
    if curl -fsSL https://openclaw.ai/install.sh -o /tmp/.oc-install.sh 2>/dev/null; then
      if bash /tmp/.oc-install.sh --no-prompt >>"$LOG" 2>&1; then
        hash -r 2>/dev/null || true
        if command -v openclaw >/dev/null 2>&1 && node_ok; then
          ok "官方安装器执行成功：Node $(node -v) / $(openclaw --version 2>/dev/null | head -1)"
          return 0
        fi
      fi
      warn "官方安装器未能自动完成（常见于已有旧 Node 的情况）"
    fi
  fi

  err "需要手动安装 Node 26，二选一："
  cat <<'EOF'

  【方式A】安装 nvm（推荐，后续可自由切换版本）
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    source ~/.zshrc      # 或 source ~/.bashrc
    nvm install 26 && nvm alias default 26
    然后重新运行本部署命令

  【方式B】官网下载安装包
    https://nodejs.org  → 下载 Node 26 (LTS) → 安装
    装完关掉终端重开，再运行本部署命令

EOF
  return 1
}

# --------- 卡点3：npm 脚本授权导致依赖不完整 ---------
ensure_openclaw(){
  step "2/6" "安装 OpenClaw"

  if command -v openclaw >/dev/null 2>&1; then
    local cv; cv="$(openclaw --version 2>/dev/null | head -1)"
    ok "已安装：$cv"
    dim "更新命令：npm install -g --allow-scripts=openclaw,@google/genai,esbuild,koffi,protobufjs openclaw@latest"
    return 0
  fi

  local npmv; npmv="$(npm -v 2>/dev/null || echo 0)"
  info "npm 版本：$npmv"
  dim "关键：必须一次性给全部 5 个包授权，否则会漏装原生依赖"

  # 一次性授权所有需要的脚本（这是实测出来的关键参数）
  local allow="openclaw,@google/genai,esbuild,koffi,protobufjs"
  info "正在安装（约 15–60 秒）..."
  if npm install -g --allow-scripts="$allow" openclaw@latest 2>&1 | tee -a "$LOG" | tail -3; then
    hash -r 2>/dev/null || true
    if command -v openclaw >/dev/null 2>&1; then
      ok "安装成功：$(openclaw --version 2>/dev/null | head -1)"
      dim "安装过程中出现 TAR_ENTRY_ERROR 警告是正常的，可忽略"
      return 0
    fi
  fi

  err "安装失败，完整日志：$LOG"
  dim "常见原因：网络超时 / 权限不足（可尝试 sudo）/ npm 缓存损坏"
  dim "重试命令：npm cache clean --force && npm install -g --allow-scripts=$allow openclaw@latest"
  return 1
}

# --------- 卡点4：gateway.mode 未设置会拒绝启动 ---------
configure_gateway(){
  step "3/6" "配置 Gateway"
  openclaw config set gateway.mode local >/dev/null 2>&1 && ok "gateway.mode = local" || warn "配置写入失败（可手动执行）"

  # 注意：openclaw config get 出于安全会把令牌显示为 __OPENCLAW_REDACTED__
  # 这是正常的"已配置"标志，不是错误。直接从配置文件读取真实值。
  local cfg="$HOME/.openclaw/openclaw.json"
  local tok=""
  if [ -f "$cfg" ]; then
    tok="$(node -e '
      try{
        const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
        const t=c?.gateway?.auth?.token;
        if(typeof t==="string" && t.length>0) process.stdout.write(t);
      }catch(e){}
    ' "$cfg" 2>/dev/null)"
  fi

  if [ -n "$tok" ]; then
    ok "访问令牌已就绪"
  else
    info "生成访问令牌..."
    openclaw doctor --fix --generate-gateway-token >/dev/null 2>&1
    if [ -f "$cfg" ] && grep -q '"token"' "$cfg" 2>/dev/null; then
      ok "令牌已生成"
    else
      warn "令牌未生成，首次打开控制台时按提示创建即可"
    fi
  fi
}

# --------- 卡点5：容器/systemd 缺失时 gateway start 失败 ---------
start_gateway(){
  step "4/6" "启动 Gateway"
  local port="$PORT_DEFAULT"

  if curl -s -m 3 "http://127.0.0.1:$port/health" 2>/dev/null | grep -q '"ok":true'; then
    ok "Gateway 已在运行（端口 $port）"
    return 0
  fi

  # 先试服务方式
  if openclaw gateway start >/dev/null 2>&1; then
    sleep 4
    if curl -s -m 3 "http://127.0.0.1:$port/health" 2>/dev/null | grep -q '"ok":true'; then
      ok "Gateway 已作为服务启动"
      return 0
    fi
  fi

  # 回退：前台模式后台运行（容器/无 systemd 环境必用）
  warn "系统服务方式不可用（容器或缺少 systemd），改用后台进程"
  dim "这是常见情况，不影响使用"
  nohup openclaw gateway run > "$HOME/.openclaw-gateway.log" 2>&1 &
  echo $! > "$HOME/.openclaw-gateway.pid"
  info "等待启动（最多 40 秒）..."
  for i in $(seq 1 20); do
    sleep 2
    if curl -s -m 3 "http://127.0.0.1:$port/health" 2>/dev/null | grep -q '"ok":true'; then
      ok "Gateway 启动成功（PID $(cat "$HOME/.openclaw-gateway.pid")）"
      return 0
    fi
  done

  err "启动超时，日志：$HOME/.openclaw-gateway.log"
  tail -8 "$HOME/.openclaw-gateway.log" 2>/dev/null | sed 's/^/    /'
  return 1
}

# --------- 卡点6：装完不知道下一步 ---------
verify_and_report(){
  step "5/6" "健康检查"
  local port="$PORT_DEFAULT"

  local h; h="$(curl -s -m 5 "http://127.0.0.1:$port/health" 2>/dev/null)"
  if echo "$h" | grep -q '"ok":true'; then
    ok "服务健康：$h"
  else
    err "健康检查未通过"
    return 1
  fi

  local code; code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:$port/" 2>/dev/null)"
  [ "$code" = "200" ] && ok "控制台可访问（HTTP 200）" || warn "控制台返回 $code"

  step "6/6" "完成"
  # 管道执行时 $0 是 bash，不是脚本路径，需要正确展示
  local self="$0"
  case "$self" in
    bash|sh|-bash|-sh|*/bash|*/sh) self="(重新运行安装命令)" ;;
  esac
  cat <<EOF

  ┌────────────────────────────────────────────────┐
  │  部署完成                                       │
  └────────────────────────────────────────────────┘

  控制台地址：  http://127.0.0.1:${port}
  查看状态：    openclaw gateway status
  查看令牌：    openclaw config get gateway.auth
  打开面板：    openclaw dashboard
  自检排错：    openclaw doctor

  下一步（必做）：
    1. 配置模型 API —— 运行  openclaw configure
       国产模型更便宜稳定，推荐 deepseek / qwen
    2. 浏览器打开上面的控制台地址，输入令牌
    3. 发一条消息，确认助手能回复

  常用命令：
    停止服务：    kill \$(cat ~/.openclaw-gateway.pid)
    查看日志：    tail -f ~/.openclaw-gateway.log
    重启服务：    ${self}

  安装日志：      $LOG

EOF
}

main(){
  banner
  ensure_node      || { err "环境准备失败，已停止"; exit 1; }
  ensure_openclaw  || { err "安装失败，已停止"; exit 1; }
  configure_gateway
  start_gateway    || { err "启动失败，已停止"; exit 1; }
  verify_and_report
}

case "${1:-}" in
  --check)  ensure_node && ok "环境符合要求" ;;
  --status) openclaw gateway status 2>&1 | head -30 ;;
  --token)
    cfg="$HOME/.openclaw/openclaw.json"
    node -e '
      try{
        const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
        const t=c?.gateway?.auth?.token;
        if(t) console.log("\n访问令牌：\n\n  "+t+"\n\n打开 http://127.0.0.1:'"$PORT_DEFAULT"' 粘贴即可\n");
        else console.log("尚未生成令牌，运行 openclaw doctor --fix --generate-gateway-token");
      }catch(e){ console.log("读取配置失败："+e.message); }
    ' "$cfg" ;;
  --stop)
    stopped=0
    # 方式1：pid 文件
    if [ -f "$HOME/.openclaw-gateway.pid" ]; then
      pid="$(cat "$HOME/.openclaw-gateway.pid" 2>/dev/null)"
      if [ -n "$pid" ] && kill "$pid" 2>/dev/null; then stopped=1; fi
      rm -f "$HOME/.openclaw-gateway.pid"
    fi
    # 方式2：按端口精准查找（父进程被杀后子进程可能残留）
    port_pids="$( (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) \
      | grep ":$PORT_DEFAULT " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)"
    if [ -n "$port_pids" ]; then
      for p in $port_pids; do kill "$p" 2>/dev/null && stopped=1; done
      sleep 2
      # 仍存活则强制结束
      for p in $port_pids; do kill -9 "$p" 2>/dev/null; done
    fi
    # 方式3：交给官方命令
    openclaw gateway stop >/dev/null 2>&1 || true
    sleep 2
    if curl -s -m 3 "http://127.0.0.1:$PORT_DEFAULT/health" >/dev/null 2>&1; then
      warn "服务仍在运行，请手动检查：ps aux | grep openclaw"
    else
      ok "服务已停止"
    fi ;;
  --report)
    # 生成排错报告：客户把这段内容发给服务商，对方一看就知道问题在哪
    echo ""
    echo "======= OpenClaw 排错报告 ======="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "系统: $(uname -s) $(uname -r) $(uname -m)"
    echo "Node: $(node -v 2>/dev/null || echo '未安装')"
    echo "npm : $(npm -v 2>/dev/null || echo '未安装')"
    echo "OpenClaw: $(openclaw --version 2>/dev/null | head -1 || echo '未安装')"
    echo "--------------------------------"
    echo -n "健康检查: "
    curl -s -m 3 "http://127.0.0.1:$PORT_DEFAULT/health" 2>/dev/null || echo "无响应"
    echo ""
    echo -n "端口 $PORT_DEFAULT: "
    (ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | grep -q ":$PORT_DEFAULT " && echo "监听中" || echo "未监听"
    echo "--------------------------------"
    echo "最近日志（最后8行）:"
    tail -8 "$HOME/.openclaw-gateway.log" 2>/dev/null | sed 's/^/  /' || echo "  无日志文件"
    echo "================================="
    echo ""
    ;;
  --help|-h)
    echo "用法: $0 [选项]"
    echo "  (无参数)   完整部署（推荐）"
    echo "  --check    只检查环境，不安装"
    echo "  --status   查看运行状态"
    echo "  --token    查看控制台访问令牌"
    echo "  --stop     停止服务"
    echo "  --help     显示帮助"
    ;;
  *) main ;;
esac
