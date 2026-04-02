#!/usr/bin/env bash
#
# OpenClaw Gateway 一键部署脚本
# - 由 APIPro 团队开发维护
# - 支持国内节点（api.wenwen-ai.com）/ 海外节点（api.apipro.ai）
# - 支持 Claude / OpenAI 格式 / Gemini / MiniMax 四种模型格式
# - 本机 Node.js 运行，自动安装环境
#
# 用法（一键部署）：
#   curl -fsSL https://raw.githubusercontent.com/yicheng0/openclaw-apipro-/main/deploy.sh | sudo bash
#
# 参数说明：
#   所有配置均在脚本运行时交互输入
#   API Key、渠道凭据均通过提示输入
#   支持环境变量预设以实现无交互部署
#
set -eo pipefail

OPENCLAW_DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
[[ "$OPENCLAW_PORT" =~ ^[0-9]+$ ]] || { echo "[ERROR] OPENCLAW_PORT 必须是数字，当前值: $OPENCLAW_PORT" >&2; exit 1; }
# pin 到一个已验证可安装的版本；如需切换可通过环境变量覆盖
OPENCLAW_NPM_SPEC="${OPENCLAW_NPM_SPEC:-openclaw@2026.3.13}"
OPENCLAW_FORCE_UPDATE="${OPENCLAW_FORCE_UPDATE:-0}"
# 用于错误提示中的 sudo 命令（curl|bash 场景下 $0 是 bash，无意义）
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/yicheng0/openclaw-apipro-/main/deploy.sh}"

# --- 颜色与输出 ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
nc='\033[0m'
info() { echo -e "${green}[INFO]${nc} $*"; }
warn() { echo -e "${yellow}[WARN]${nc} $*"; }
err()  { echo -e "${red}[ERROR]${nc} $*"; }

# --- 失败时清理 ---
_cleanup() {
  local code=$?
  if [ $code -ne 0 ]; then
    err "部署失败（退出码: $code），正在清理..."
    rm -f "${OPENCLAW_DATA_DIR}/openclaw.json"
  fi
}
trap '_cleanup' EXIT

# --- 检测是否需要 root ---
is_root() {
  [ "$(id -u)" = "0" ]
}

# --- 读取用户输入（带默认环境变量）---
read_token() {
  local env_name="$1"
  local prompt="$2"
  local val="${!env_name}"
  if [ -n "$val" ]; then
    echo "$val"
    return
  fi
  while true; do
    read_input "$prompt" val
    val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
    warn "不能为空，请重新输入。"
  done
}

# --- 从终端读取一行输入（兼容 curl|bash 场景）---
read_input() {
  local prompt="$1"
  local varname="$2"
  if [ -t 0 ]; then
    read -r -p "$prompt" "$varname"
  else
    read -r -p "$prompt" "$varname" </dev/tty
  fi
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
  if ! is_root; then
    err "安装 jq 需要 root。请使用: sudo bash $SCRIPT_URL"
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

# --- 预设模型菜单（选类型后展示内置列表）---
# 设置全局变量：MODEL_ID, MODEL_NAME
choose_preset_model() {
  local type="$1"

  echo ""
  case "$type" in
    claude)
      echo "  请选择 Claude 模型："
      echo "    [1] claude-sonnet-4-6-20260218  Claude Sonnet 4.6（推荐）★"
      echo "    [2] 自定义模型 ID..."
      ;;
    openai)
      echo "  请选择 OpenAI 模型："
      echo "    [1] gpt-5.4               GPT-5.4（推荐）★"
      echo "    [2] 自定义模型 ID..."
      ;;
    gemini)
      echo "  请选择 Gemini 模型："
      echo "    [1] gemini-3-flash-preview  Gemini 3 Flash（推荐）★"
      echo "    [2] 自定义模型 ID..."
      ;;
    minimax)
      echo "  请选择 MiniMax 模型："
      echo "    [1] minimax-m2.7         MiniMax M2.7（推荐）★"
      echo "    [2] 自定义模型 ID..."
      ;;
  esac
  echo ""

  while true; do
    read_input "  请输入选项（回车默认 1）: " mchoice
    mchoice="${mchoice:-1}"

    if [ "$mchoice" = "2" ]; then
      # 自定义输入
      while true; do
        read_input "  请输入自定义模型 ID: " custom_id
        custom_id=$(echo "$custom_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$custom_id" ]; then
          MODEL_ID="$custom_id"
          MODEL_NAME="$custom_id"
          return
        fi
        warn "不能为空，请重新输入。"
      done
    fi

    case "$type-$mchoice" in
      claude-1) MODEL_ID="claude-sonnet-4-6-20260218"; MODEL_NAME="Claude Sonnet 4.6"; return ;;
      openai-1) MODEL_ID="gpt-5.4";            MODEL_NAME="GPT-5.4";           return ;;
      gemini-1) MODEL_ID="gemini-3-flash-preview"; MODEL_NAME="Gemini 3 Flash"; return ;;
      minimax-1) MODEL_ID="minimax-m2.7";      MODEL_NAME="MiniMax M2.7";      return ;;
      *) warn "请输入 1 或 2。" ;;
    esac
  done
}

# --- 选择接入节点 ---
# 设置全局变量：APIPRO_BASE_URL, REGION_NAME
choose_region() {
  if [ -n "${APIPRO_REGION:-}" ]; then
    case "$APIPRO_REGION" in
      cn)
        APIPRO_BASE_URL="https://api.wenwen-ai.com"
        REGION_NAME="国内节点"
        ;;
      global)
        APIPRO_BASE_URL="https://api.apipro.ai"
        REGION_NAME="海外节点"
        ;;
      *)
        err "未知节点: $APIPRO_REGION（支持 cn / global）"; exit 1 ;;
    esac
    return
  fi

  echo ""
  echo "  请选择接入节点："
  echo "    [1] 🇨🇳  国内节点  —  api.wenwen-ai.com  （中国大陆推荐）"
  echo "    [2] 🌏  海外节点  —  api.apipro.ai       （境外服务器推荐）"
  echo ""

  while true; do
    read_input "  请输入 1-2（回车默认选 1）: " rchoice
    rchoice="${rchoice:-1}"
    case "$rchoice" in
      1)
        APIPRO_BASE_URL="https://api.wenwen-ai.com"
        REGION_NAME="国内节点"
        break
        ;;
      2)
        APIPRO_BASE_URL="https://api.apipro.ai"
        REGION_NAME="海外节点"
        break
        ;;
      *) warn "请输入 1 或 2。" ;;
    esac
  done
}

# --- 选择消息渠道 ---
# 设置全局变量：CHANNEL_TYPE
choose_channel() {
  if [ -n "${CHANNEL_TYPE:-}" ]; then
    case "$CHANNEL_TYPE" in
      feishu|telegram) ;;
      *) err "未知渠道类型: $CHANNEL_TYPE（支持 feishu / telegram）"; exit 1 ;;
    esac
    return
  fi

  echo ""
  echo "  请选择消息渠道："
  echo "    [1] 飞书（推荐）"
  echo "    [2] Telegram"
  echo ""

  while true; do
    read_input "  请输入 1-2（回车默认选 1）: " cchoice
    cchoice="${cchoice:-1}"
    case "$cchoice" in
      1) CHANNEL_TYPE=feishu;   break ;;
      2) CHANNEL_TYPE=telegram; break ;;
      *) warn "请输入 1 或 2。" ;;
    esac
  done
}

# --- 选择模型类型 ---
# 设置全局变量：MODEL_TYPE, MODEL_ID, MODEL_NAME, PROVIDER_NAME
choose_model() {
  # 支持环境变量预设跳过交互
  if [ -n "${APIPRO_MODEL_TYPE:-}" ]; then
    MODEL_TYPE="$APIPRO_MODEL_TYPE"
  else
    echo ""
    echo "  请选择使用的模型类型："
    echo "    [1] OpenAI 格式  — GPT-5.4（推荐，价格实惠）"
    echo "    [2] MiniMax 系列 — 国产大模型"
    echo "    [3] Gemini 系列  — Google AI"
    echo "    [4] Claude 系列  — 原生 Anthropic 格式"
    echo ""
    while true; do
      read_input "请输入 1-4（直接回车默认选 1）: " choice
      choice="${choice:-1}"
      case "$choice" in
        1) MODEL_TYPE=openai;  break ;;
        2) MODEL_TYPE=minimax; break ;;
        3) MODEL_TYPE=gemini;  break ;;
        4) MODEL_TYPE=claude;  break ;;
        *) warn "请输入 1、2、3 或 4。" ;;
      esac
    done
  fi

  case "$MODEL_TYPE" in
    claude)
      PROVIDER_NAME="apipro-claude"
      ;;
    openai)
      PROVIDER_NAME="apipro-openai"
      ;;
    gemini)
      PROVIDER_NAME="apipro-gemini"
      ;;
    minimax)
      PROVIDER_NAME="apipro-minimax"
      ;;
    *)
      err "未知模型类型: $MODEL_TYPE"
      exit 1
      ;;
  esac

  # 支持环境变量预设模型 ID（跳过预设菜单）
  if [ -n "${APIPRO_MODEL_ID:-}" ]; then
    MODEL_ID="$APIPRO_MODEL_ID"
    MODEL_NAME="${APIPRO_MODEL_NAME:-$MODEL_ID}"
  else
    choose_preset_model "$MODEL_TYPE"
  fi

  info "已选择: [$MODEL_TYPE] $MODEL_ID"
}

# --- 生成 openclaw.json ---
write_openclaw_config() {
  local data_dir="$1"
  local apipro_key="$2"
  local channel_type="$3"
  local feishu_app_id="$4"
  local feishu_app_secret="$5"
  local telegram_token="$6"
  local base_url="$7"
  local provider_name="$8"
  local model_id="$9"
  local gateway_token
  gateway_token=$(openssl rand -hex 16 2>/dev/null \
    || head -c 16 /dev/urandom 2>/dev/null | od -A n -t x1 | tr -d ' \n' \
    || echo "fallback-$(date +%s)-$$")

  mkdir -p "$data_dir/workspace"
  local cfg_path="$data_dir/openclaw.json"

  # 构建 channels JSON 对象（按渠道类型分支）
  local channels_json
  if [ "$channel_type" = "feishu" ]; then
    channels_json=$(jq -n \
      --arg appId "$feishu_app_id" \
      --arg appSecret "$feishu_app_secret" \
      '{
        feishu: {
          enabled: true,
          dmPolicy: "pairing",
          groupPolicy: "allowlist",
          accounts: {
            main: { appId: $appId, appSecret: $appSecret }
          }
        }
      }')
  else
    channels_json=$(jq -n \
      --arg tg "$telegram_token" \
      '{
        telegram: {
          enabled: true,
          dmPolicy: "pairing",
          botToken: $tg,
          groupPolicy: "open",
          streaming: "off"
        }
      }')
  fi

  local installed_ver
  installed_ver=$(openclaw --version 2>/dev/null || echo "unknown")

  # 使用 jq 安全生成完整 JSON（避免 token 中的特殊字符问题）
  # 所有 4 个 provider 均写入配置，用同一个 APIPro API Key
  jq -n \
    --arg apikey "$apipro_key" \
    --argjson channels "$channels_json" \
    --arg gw "$gateway_token" \
    --arg workspace "$data_dir/workspace" \
    --argjson port "$OPENCLAW_PORT" \
    --arg defaultModel "$provider_name/$model_id" \
    --arg baseUrl "$base_url" \
    --arg version "$installed_ver" \
    '{
      meta: { lastTouchedVersion: $version, lastTouchedAt: (now | todate) },
      models: {
        mode: "merge",
        providers: {
          "apipro-openai": {
            baseUrl: "\($baseUrl)/v1",
            apiKey: $apikey,
            api: "openai-completions",
            models: [
              { id: "gpt-5.4", name: "GPT-5.4", reasoning: false, input: ["text", "image"], contextWindow: 200000, maxTokens: 8192 }
            ]
          },
          "apipro-minimax": {
            baseUrl: "\($baseUrl)/v1",
            apiKey: $apikey,
            api: "openai-completions",
            models: [
              { id: "minimax-m2.7", name: "MiniMax M2.7", reasoning: false, input: ["text", "image"], contextWindow: 200000, maxTokens: 8192 }
            ]
          },
          "apipro-gemini": {
            baseUrl: "\($baseUrl)/v1beta",
            apiKey: $apikey,
            api: "google-generative-ai",
            models: [
              { id: "gemini-3-flash-preview", name: "Gemini 3 Flash", reasoning: false, input: ["text", "image"], contextWindow: 200000, maxTokens: 8192 }
            ]
          },
          "apipro-claude": {
            baseUrl: $baseUrl,
            apiKey: $apikey,
            api: "anthropic-messages",
            models: [
              { id: "claude-sonnet-4-6-20260218", name: "Claude Sonnet 4.6", reasoning: false, input: ["text", "image"], contextWindow: 200000, maxTokens: 8192 }
            ]
          }
        }
      },
      agents: {
        defaults: {
          model: { primary: $defaultModel },
          workspace: $workspace,
          maxConcurrent: 4,
          subagents: { maxConcurrent: 8 },
          compaction: { mode: "safeguard" }
        }
      },
      channels: $channels,
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

  if ! is_root; then
    err "安装 Node.js 需要 root。请使用: sudo bash $SCRIPT_URL"
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
  local current_ver
  npm_global=$(npm root -g 2>/dev/null | sed 's|/node_modules$|/bin|') || true
  [[ -n "$npm_global" && ":$PATH:" != *":$npm_global:"* ]] && export PATH="$npm_global:$PATH"

  # 默认优先复用已安装版本，避免上游 latest 失效时影响重复执行
  if command -v openclaw &>/dev/null; then
    current_ver=$(openclaw --version 2>/dev/null || echo "unknown")
    if [ "$OPENCLAW_FORCE_UPDATE" != "1" ]; then
      info "openclaw 已安装: $current_ver"
      info "跳过更新；如需强制更新，设置 OPENCLAW_FORCE_UPDATE=1"
      return 0
    fi
    info "检测到 OPENCLAW_FORCE_UPDATE=1，准备重新安装 $OPENCLAW_NPM_SPEC"
  else
    info "正在安装 openclaw ($OPENCLAW_NPM_SPEC)..."
  fi

  if ! npm install -g "$OPENCLAW_NPM_SPEC"; then
    err "openclaw 安装失败：$OPENCLAW_NPM_SPEC"
    err "上游 latest 版本偶尔会因为依赖发布异常导致 ETARGET。"
    err "可改用已验证版本，例如：OPENCLAW_NPM_SPEC=openclaw@2026.3.13 sudo ./deploy.sh"
    exit 1
  fi

  # 再次刷新路径（仅在尚未加入时追加，避免 PATH 重复）
  npm_global=$(npm root -g 2>/dev/null | sed 's|/node_modules$|/bin|') || true
  [[ -n "$npm_global" && ":$PATH:" != *":$npm_global:"* ]] && export PATH="$npm_global:$PATH"

  if ! command -v openclaw &>/dev/null; then
    err "openclaw 安装失败，请手动执行: npm install -g $OPENCLAW_NPM_SPEC"
    exit 1
  fi
  info "openclaw 安装完成: $(openclaw --version 2>/dev/null || echo 'OK')"
}

# --- 启动 Gateway ---
run_node() {
  # 先用 openclaw 自带命令停掉所有旧实例
  openclaw gateway stop 2>/dev/null || true
  pkill -f "openclaw-gateway" 2>/dev/null || true
  sleep 1

  info "正在启动 OpenClaw Gateway (端口 $OPENCLAW_PORT)..."
  # 清空旧日志，避免 grep "listening on" 匹配上一次运行的记录
  : > "${OPENCLAW_DATA_DIR}/gateway.log"
  # 用 HOME 显式传递，确保后台进程能找到 ~/.openclaw/openclaw.json
  nohup bash -c "HOME=\"$HOME\" openclaw gateway --port \"$OPENCLAW_PORT\"" \
    >> "${OPENCLAW_DATA_DIR}/gateway.log" 2>&1 &
  local pid=$!
  echo "$pid" > "${OPENCLAW_DATA_DIR}/gateway.pid"

  # 等待 Gateway 启动（最多 60 秒），每秒显示进度点
  printf "${green}[INFO]${nc} 连接中"
  local i=0
  local started=0
  local crashed=0
  while [ $i -lt 60 ]; do
    sleep 1
    i=$((i+1))
    printf "."
    if grep -q "listening on" "${OPENCLAW_DATA_DIR}/gateway.log" 2>/dev/null; then
      started=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      crashed=1
      break
    fi
  done
  echo ""  # 换行

  if [ $started -eq 1 ]; then
    info "Gateway 已成功启动 ✓  (PID: $pid)"
  elif [ $crashed -eq 1 ]; then
    warn "Gateway 进程已意外退出，请检查日志: ${OPENCLAW_DATA_DIR}/gateway.log"
  elif kill -0 "$pid" 2>/dev/null; then
    info "Gateway 进程运行中（PID: $pid），正在初始化，稍后即可使用"
    info "查看连接状态: tail -f ${OPENCLAW_DATA_DIR}/gateway.log"
  else
    warn "Gateway 进程似乎已退出，请检查日志: ${OPENCLAW_DATA_DIR}/gateway.log"
  fi
}

# --- 主流程 ---
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║                                                          ║"
  echo "║          OpenClaw Gateway  ·  by APIPro Team            ║"
  echo "║             智能 AI 网关  ·  一键部署工具                ║"
  echo "║                                                          ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  # 数据目录
  if [ ! -d "$OPENCLAW_DATA_DIR" ]; then
    if ! is_root; then
      err "创建 $OPENCLAW_DATA_DIR 需要 root。请使用: sudo bash $SCRIPT_URL"
      exit 1
    fi
    mkdir -p "$OPENCLAW_DATA_DIR"
  fi

  # --- 第一步：安装运行环境 ---
  ensure_node
  ensure_jq
  ensure_openclaw

  # --- 第二步：收集配置 ---
  # 选择接入节点
  choose_region
  info "接入节点: $REGION_NAME  ($APIPRO_BASE_URL)"

  echo ""
  info "请在控制台获取 API Key: $APIPRO_BASE_URL"
  APIPRO_API_KEY=$(read_token "APIPRO_API_KEY" "请输入 API Key: ")

  # 选择消息渠道
  choose_channel

  if [ "$CHANNEL_TYPE" = "feishu" ]; then
    echo ""
    info "请在飞书开放平台创建企业自建应用并获取凭据"
    info "地址：https://open.feishu.cn/app"
    FEISHU_APP_ID=$(read_token "FEISHU_APP_ID" "请输入飞书 App ID（格式 cli_xxxx）: ")
    FEISHU_APP_SECRET=$(read_token "FEISHU_APP_SECRET" "请输入飞书 App Secret: ")
  else
    echo ""
    info "请在 Telegram @BotFather 创建 Bot 并获取 Token"
    TELEGRAM_BOT_TOKEN=$(read_token "TELEGRAM_BOT_TOKEN" "请输入 Telegram Bot Token: ")
  fi

  # 选择模型类型
  choose_model

  # --- 第三步：写入配置并启动 ---
  write_openclaw_config "$OPENCLAW_DATA_DIR" "$APIPRO_API_KEY" "$CHANNEL_TYPE" "$FEISHU_APP_ID" "$FEISHU_APP_SECRET" "$TELEGRAM_BOT_TOKEN" "$APIPRO_BASE_URL" "$PROVIDER_NAME" "$MODEL_ID"
  run_node

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo -e "║            ${green}部署成功  ✓   Gateway 运行中${nc}                ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  节点  : $REGION_NAME  ($APIPRO_BASE_URL)"
  echo "  渠道  : $CHANNEL_TYPE"
  echo "  模型  : $MODEL_NAME  ($MODEL_TYPE 格式)"
  echo "  网关  : http://127.0.0.1:$OPENCLAW_PORT"
  echo "  配置  : $OPENCLAW_DATA_DIR/openclaw.json"
  echo ""
  if [ "$CHANNEL_TYPE" = "feishu" ]; then
    echo "  → 在飞书中将机器人添加到会话，发送消息即可开始使用"
  else
    echo "  → 在 Telegram 向你的 Bot 发送 /start 即可开始使用"
  fi
  echo "  → 查看日志: tail -f $OPENCLAW_DATA_DIR/gateway.log"
  echo ""
}

main "$@"
