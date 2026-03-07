#!/usr/bin/env bash
#
# OpenClaw 一键部署脚本（Breakout 版）
# - 使用 Breakout (wenwen-ai) API
# - 支持 Claude / OpenAI 格式 / Gemini 三种模型格式
# - 本机 Node.js 运行，自动安装环境
#
# 用法（一键部署）：
#   curl -fsSL https://你的域名/deploy.sh | bash
#
# 参数说明：
#   所有配置均在脚本运行时交互输入
#   Breakout API Key 和 Telegram Bot Token 均通过提示输入
#
set -e

OPENCLAW_DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"

# --- 颜色与输出 ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
nc='\033[0m'
info() { echo -e "${green}[INFO]${nc} $*"; }
warn() { echo -e "${yellow}[WARN]${nc} $*"; }
err()  { echo -e "${red}[ERROR]${nc} $*"; }

# --- 检测 root / sudo ---
need_sudo() {
  if [ -w "$OPENCLAW_DATA_DIR" ] 2>/dev/null || [ ! -d "$OPENCLAW_DATA_DIR" ]; then
    return 1
  fi
  [ "$(id -u)" != "0" ]
}

# --- 读取用户输入（带默认环境变量）---
read_token() {
  local name="$1"
  local env_name="$2"
  local prompt="$3"
  local val="${!env_name}"
  if [ -n "$val" ]; then
    echo "$val"
    return
  fi
  while true; do
    if [ -t 0 ]; then
      read -r -p "$prompt" val
    else
      read -r -p "$prompt" val </dev/tty
    fi
    val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
    warn "不能为空，请重新输入。"
  done
}

# --- 检测 jq，不存在则自动安装 ---
ensure_jq() {
  if command -v jq &>/dev/null; then
    return 0
  fi
  if [ "$(uname -s)" != "Linux" ]; then
    err "生成配置需要 jq。请安装 jq 后重试。"
    exit 1
  fi
  if [ "$(id -u)" != "0" ]; then
    err "安装 jq 需要 root。请使用: sudo $0"
    exit 1
  fi
  if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq jq
  elif command -v dnf &>/dev/null; then
    dnf install -y jq
  elif command -v yum &>/dev/null; then
    yum install -y jq
  else
    err "请先安装 jq (apt/dnf/yum install jq)。"
    exit 1
  fi
}

# --- 选择模型类型 ---
# 设置全局变量：MODEL_TYPE, MODEL_ID, MODEL_NAME, PROVIDER_NAME, BASE_URL, API_TYPE
choose_model() {
  # 支持环境变量预设跳过交互
  if [ -n "${BREAKOUT_MODEL_TYPE:-}" ]; then
    MODEL_TYPE="$BREAKOUT_MODEL_TYPE"
  else
    echo ""
    echo "  请选择使用的模型类型："
    echo "    [1] Claude 系列（如 claude-sonnet-4-6）— 原生 Anthropic 格式（推荐）"
    echo "    [2] OpenAI 格式（如 gpt-4o、Kimi、DeepSeek 等）"
    echo "    [3] Gemini 系列（如 gemini-3-flash-preview）"
    echo ""
    while true; do
      if [ -t 0 ]; then
        read -r -p "请输入 1、2 或 3（直接回车默认选 1）: " choice
      else
        read -r -p "请输入 1、2 或 3（直接回车默认选 1）: " choice </dev/tty
      fi
      choice="${choice:-1}"
      case "$choice" in
        1) MODEL_TYPE=claude; break ;;
        2) MODEL_TYPE=openai; break ;;
        3) MODEL_TYPE=gemini; break ;;
        *) warn "请输入 1、2 或 3。" ;;
      esac
    done
  fi

  case "$MODEL_TYPE" in
    claude)
      PROVIDER_NAME="breakout-claude"
      BASE_URL="https://breakout.wenwen-ai.com"
      API_TYPE="anthropic-messages"
      DEFAULT_MODEL_ID="claude-sonnet-4-6"
      DEFAULT_MODEL_NAME="Claude Sonnet 4.6"
      ;;
    openai)
      PROVIDER_NAME="breakout-openai"
      BASE_URL="https://breakout.wenwen-ai.com/v1"
      API_TYPE="openai-completions"
      DEFAULT_MODEL_ID="gpt-4o"
      DEFAULT_MODEL_NAME="GPT-4o"
      ;;
    gemini)
      PROVIDER_NAME="breakout-gemini"
      BASE_URL="https://breakout.wenwen-ai.com/v1beta"
      API_TYPE="google-generative-ai"
      DEFAULT_MODEL_ID="gemini-3-flash-preview"
      DEFAULT_MODEL_NAME="Gemini 3 Flash"
      ;;
    *)
      err "未知模型类型: $MODEL_TYPE"
      exit 1
      ;;
  esac

  # 支持环境变量预设模型 ID
  if [ -n "${BREAKOUT_MODEL_ID:-}" ]; then
    MODEL_ID="$BREAKOUT_MODEL_ID"
    MODEL_NAME="${BREAKOUT_MODEL_NAME:-$MODEL_ID}"
  else
    echo ""
    echo "  当前选择: $MODEL_TYPE 格式，默认模型: $DEFAULT_MODEL_ID"
    if [ -t 0 ]; then
      read -r -p "  请输入模型 ID（直接回车使用默认 $DEFAULT_MODEL_ID）: " input_model
    else
      read -r -p "  请输入模型 ID（直接回车使用默认 $DEFAULT_MODEL_ID）: " input_model </dev/tty
    fi
    input_model=$(echo "$input_model" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$input_model" ]; then
      MODEL_ID="$input_model"
      MODEL_NAME="$input_model"
    else
      MODEL_ID="$DEFAULT_MODEL_ID"
      MODEL_NAME="$DEFAULT_MODEL_NAME"
    fi
  fi

  info "已选择: [$MODEL_TYPE] $MODEL_ID"
}

# --- 生成 openclaw.json ---
write_openclaw_config() {
  local data_dir="$1"
  local breakout_key="$2"
  local telegram_token="$3"
  local gateway_token
  gateway_token=$(openssl rand -hex 16 2>/dev/null || echo "fallback-$(date +%s)-$$")

  mkdir -p "$data_dir/workspace"
  local cfg_path="$data_dir/openclaw.json"

  # 使用 jq 安全生成 JSON（避免 token 中的特殊字符问题）
  jq -n \
    --arg apikey "$breakout_key" \
    --arg tg "$telegram_token" \
    --arg gw "$gateway_token" \
    --arg workspace "$data_dir/workspace" \
    --argjson port "$OPENCLAW_PORT" \
    --arg provider "$PROVIDER_NAME" \
    --arg baseUrl "$BASE_URL" \
    --arg api "$API_TYPE" \
    --arg modelId "$MODEL_ID" \
    --arg modelName "$MODEL_NAME" \
    '{
      meta: { lastTouchedVersion: "2026.2.3-1", lastTouchedAt: (now | todate) },
      models: {
        mode: "merge",
        providers: {
          ($provider): {
            baseUrl: $baseUrl,
            apiKey: $apikey,
            api: $api,
            models: [
              {
                id: $modelId,
                name: $modelName,
                reasoning: false,
                input: ["text", "image"],
                contextWindow: 200000,
                maxTokens: 8192
              }
            ]
          }
        }
      },
      agents: {
        defaults: {
          model: { primary: ($provider + "/" + $modelId) },
          workspace: $workspace,
          maxConcurrent: 4,
          subagents: { maxConcurrent: 8 },
          compaction: { mode: "safeguard" }
        }
      },
      channels: {
        telegram: {
          enabled: true,
          dmPolicy: "pairing",
          botToken: $tg,
          groupPolicy: "open",
          streaming: "off"
        }
      },
      gateway: {
        port: $port,
        mode: "local",
        bind: "loopback",
        auth: { mode: "token", token: $gw }
      }
    }' > "$cfg_path"

  chmod 600 "$cfg_path"
  info "已生成配置: $cfg_path"
}

# --- 自动安装 Node.js 22 ---
ensure_node() {
  if command -v node &>/dev/null; then
    local v
    v=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo "0")
    if [ "${v:-0}" -ge 18 ]; then
      info "Node.js 已就绪: $(node -v)"
      return 0
    fi
    warn "当前 Node.js 版本过低 ($(node -v))，正在升级到 Node.js 22..."
  else
    info "未检测到 Node.js，正在安装 Node.js 22..."
  fi

  if [ "$(uname -s)" != "Linux" ]; then
    err "请先安装 Node.js 22+，参考: https://nodejs.org"
    exit 1
  fi

  if [ "$(id -u)" != "0" ]; then
    err "安装 Node.js 需要 root。请使用: sudo $0"
    exit 1
  fi

  if command -v apt-get &>/dev/null; then
    # Debian / Ubuntu
    apt-get install -y -qq ca-certificates curl gnupg 2>/dev/null || true
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y -qq nodejs
  elif command -v dnf &>/dev/null; then
    # RHEL 8+ / Fedora / Rocky / Alma
    dnf module disable nodejs -y 2>/dev/null || true
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
    dnf install -y nodejs
  elif command -v yum &>/dev/null; then
    # CentOS 7
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
    yum install -y nodejs
  else
    err "不支持的包管理器，请手动安装 Node.js 22+: https://nodejs.org"
    exit 1
  fi

  # 刷新 PATH（NodeSource 安装后路径可能未生效）
  export PATH="/usr/bin:/usr/local/bin:$PATH"

  if ! command -v node &>/dev/null; then
    err "Node.js 安装失败，请手动安装后重试。"
    exit 1
  fi
  info "Node.js 安装完成: $(node -v)"
}

# --- 安装 openclaw CLI ---
ensure_openclaw() {
  # 刷新 PATH，确保 npm 全局路径可用
  local npm_global
  npm_global=$(npm root -g 2>/dev/null | sed 's|/node_modules$|/bin|') || true
  [ -n "$npm_global" ] && export PATH="$npm_global:$PATH"

  info "正在安装 openclaw（最新版）..."
  npm install -g openclaw@latest

  # 再次刷新路径
  npm_global=$(npm root -g 2>/dev/null | sed 's|/node_modules$|/bin|') || true
  [ -n "$npm_global" ] && export PATH="$npm_global:$PATH"

  if ! command -v openclaw &>/dev/null; then
    err "openclaw 安装失败，请手动执行: npm install -g openclaw@latest"
    exit 1
  fi
  info "openclaw 安装完成: $(openclaw --version 2>/dev/null || echo 'OK')"
}

# --- 启动 Gateway ---
run_node() {
  export OPENCLAW_HOME="$OPENCLAW_DATA_DIR"

  # 若已有旧进程则停掉
  local pid_file="${OPENCLAW_DATA_DIR}/gateway.pid"
  if [ -f "$pid_file" ]; then
    local old_pid
    old_pid=$(cat "$pid_file")
    if kill -0 "$old_pid" 2>/dev/null; then
      info "停止旧 Gateway 进程 (PID: $old_pid)..."
      kill "$old_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  info "正在启动 OpenClaw Gateway (端口 $OPENCLAW_PORT)..."
  nohup openclaw gateway --port "$OPENCLAW_PORT" >> "${OPENCLAW_DATA_DIR}/gateway.log" 2>&1 &
  echo $! > "$pid_file"
  info "Gateway 已在后台启动，PID: $(cat "$pid_file")"
  info "日志: ${OPENCLAW_DATA_DIR}/gateway.log"
}

# --- 主流程 ---
main() {
  echo ""
  echo "=============================================="
  echo "  OpenClaw 一键部署（Breakout 版）"
  echo "=============================================="
  echo ""

  # 数据目录
  if [ ! -d "$OPENCLAW_DATA_DIR" ]; then
    if need_sudo; then
      err "创建 $OPENCLAW_DATA_DIR 需要 root。请使用: sudo $0"
      exit 1
    fi
    mkdir -p "$OPENCLAW_DATA_DIR"
  fi

  # --- 第一步：安装运行环境 ---
  ensure_node
  ensure_jq
  ensure_openclaw

  # --- 第二步：收集配置 ---
  BREAKOUT_API_KEY="${BREAKOUT_API_KEY:-}"
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

  echo ""
  info "请在 Breakout 获取 API Key: https://breakout.wenwen-ai.com"
  BREAKOUT_API_KEY=$(read_token "Breakout API Key" "BREAKOUT_API_KEY" "请输入 Breakout API Token: ")

  echo ""
  info "请在 Telegram @BotFather 创建 Bot 并获取 Token"
  TELEGRAM_BOT_TOKEN=$(read_token "Telegram Bot Token" "TELEGRAM_BOT_TOKEN" "请输入 Telegram Bot Token: ")

  # 选择模型类型
  choose_model

  # --- 第三步：写入配置并启动 ---
  write_openclaw_config "$OPENCLAW_DATA_DIR" "$BREAKOUT_API_KEY" "$TELEGRAM_BOT_TOKEN"
  run_node

  echo ""
  echo "=============================================="
  echo -e "  ${green}部署完成${nc}"
  echo "=============================================="
  echo "  - 模型: $MODEL_NAME ($MODEL_TYPE 格式，via Breakout)"
  echo "  - 网关: http://127.0.0.1:$OPENCLAW_PORT"
  echo "  - 配置: $OPENCLAW_DATA_DIR/openclaw.json"
  echo ""

  # 可选：立即配对（支持 curl | bash 模式）
  if [ -z "${CI:-}" ]; then
    echo "  是否现在配对？请在 Telegram 向你的 Bot 发送 /start，"
    echo "  将显示的配对码（如 ZPGUDP8H）输入下方，直接回车则跳过。"
    echo ""
    if [ -t 0 ]; then
      read -r -p "请输入配对码（直接回车跳过）: " pairing_code
    else
      read -r -p "请输入配对码（直接回车跳过）: " pairing_code </dev/tty
    fi
    pairing_code=$(echo "$pairing_code" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$pairing_code" ]; then
      if OPENCLAW_HOME="$OPENCLAW_DATA_DIR" openclaw pairing approve telegram "$pairing_code" 2>/dev/null; then
        info "配对成功，该用户已可在私聊中使用 Bot。"
      else
        warn "配对失败，请确认配对码正确且 Gateway 已运行。"
        warn "稍后可执行: OPENCLAW_HOME=$OPENCLAW_DATA_DIR openclaw pairing approve telegram <配对码>"
      fi
    fi
  fi
  echo ""
}

main "$@"
