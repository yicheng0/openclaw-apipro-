# OpenClaw 一键部署（APIPro 版）

在新服务器上一条命令部署 OpenClaw AI 网关，接入 **APIPro**，支持飞书 / Telegram 两种消息渠道，以及 Claude / OpenAI / Gemini / MiniMax 四种模型格式。

> **系统要求：** Linux 服务器（推荐 Ubuntu 20.04+/Debian 11+/CentOS 7+），Windows/macOS 暂不支持。

## 需要准备

1. **APIPro API Key** — 在 [APIPro](https://api.apipro.ai) 注册并获取（国内用户访问 [wenwen-ai.com](https://api.wenwen-ai.com)）
2. **消息渠道凭据**，二选一：
   - **飞书**：在[飞书开放平台](https://open.feishu.cn/app)创建企业自建应用，获取 App ID 和 App Secret
   - **Telegram**：在 @BotFather 创建 Bot，获取 Bot Token

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/yicheng0/openclaw-apipro-/main/deploy.sh | bash
```

按提示依次：

1. 选择接入节点：**国内节点**（api.wenwen-ai.com）或**海外节点**（api.apipro.ai）
2. 输入 **APIPro API Key**
3. 选择消息渠道：**飞书** 或 **Telegram**，并填入对应凭据
4. 选择模型类型和具体模型（支持内置预设或自定义输入）

## 支持的模型格式

| 类型 | API 格式 | 内置预设模型 |
|------|---------|---------|
| Claude 系列 | anthropic-messages | `claude-sonnet-4-6-20260218`（推荐） |
| OpenAI 格式 | openai-completions | `gpt-5.4`（推荐） |
| Gemini 系列 | google-generative-ai | `gemini-3-flash-preview`（推荐） |
| MiniMax 系列 | openai-completions | `minimax-m2.7`（推荐） |

## 环境变量（可选）

预设环境变量可跳过交互，实现全自动部署。

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `APIPRO_API_KEY` | APIPro API Key | - |
| `APIPRO_REGION` | 接入节点（`cn` / `global`） | - |
| `APIPRO_MODEL_TYPE` | 模型类型（`claude` / `openai` / `gemini` / `minimax`） | - |
| `APIPRO_MODEL_ID` | 模型 ID | - |
| `APIPRO_MODEL_NAME` | 模型显示名称（配合 `APIPRO_MODEL_ID` 使用） | 同 Model ID |
| `CHANNEL_TYPE` | 消息渠道（`feishu` / `telegram`） | - |
| `FEISHU_APP_ID` | 飞书应用 App ID | - |
| `FEISHU_APP_SECRET` | 飞书应用 App Secret | - |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token | - |
| `OPENCLAW_DATA_DIR` | 数据目录 | `~/.openclaw` |
| `OPENCLAW_PORT` | 网关端口 | `18789` |
| `OPENCLAW_NPM_SPEC` | 要安装的 openclaw npm 版本 | `openclaw@2026.3.13` |
| `OPENCLAW_FORCE_UPDATE` | 已安装时是否强制重装（`1` 为重装） | `0` |

### 非交互式部署示例

```bash
# 飞书 + Claude，国内节点
APIPRO_API_KEY=your_key \
APIPRO_REGION=cn \
CHANNEL_TYPE=feishu \
FEISHU_APP_ID=cli_xxxx \
FEISHU_APP_SECRET=your_secret \
APIPRO_MODEL_TYPE=claude \
sudo bash deploy.sh
```

```bash
# Telegram + GPT，海外节点
APIPRO_API_KEY=your_key \
APIPRO_REGION=global \
CHANNEL_TYPE=telegram \
TELEGRAM_BOT_TOKEN=your_bot_token \
APIPRO_MODEL_TYPE=openai \
sudo bash deploy.sh
```

### openclaw 安装报 `ETARGET` 怎么办

如果上游 `openclaw@latest` 引用了尚未发布或已撤回的依赖版本，`npm` 会报：

```text
npm error code ETARGET
npm error notarget No matching version found for xxx
```

此仓库默认已 pin 到一个已验证版本，也可手动指定：

```bash
OPENCLAW_NPM_SPEC=openclaw@2026.3.13 sudo bash deploy.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `deploy.sh` | 一键部署脚本 |

## 相关链接

- [APIPro](https://api.apipro.ai) — AI API 网关（海外）
- [wenwen-ai.com](https://api.wenwen-ai.com) — AI API 网关（国内）
- [OpenClaw](https://github.com/openclaw/openclaw) — 开源 AI 助手框架

## License

MIT
