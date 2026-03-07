# OpenClaw 一键部署（Breakout 版）

在新服务器上一条命令部署 OpenClaw Telegram Bot，**必须使用 Breakout**，支持 Claude / OpenAI 格式 / Gemini 三种模型。

> **系统要求：** Linux 服务器（推荐 Ubuntu 20.04+/Debian 11+/CentOS 7+），Windows/macOS 暂不支持。

## 需要填写

1. **Breakout API Token** — 在 [Breakout](https://breakout.wenwen-ai.com) 注册并获取
2. **Telegram Bot Token** — 在 Telegram 找 @BotFather 创建 Bot 后获取

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/yicheng0/openclaw-/main/deploy.sh | bash
```

按提示依次：

1. 脚本自动安装 **Node.js 22** 和 **openclaw**（无需手动操作）
2. 输入 **Breakout API Token**（在 [Breakout](https://breakout.wenwen-ai.com) 注册后获取）
3. 输入 **Telegram Bot Token**（在 @BotFather 创建 Bot 后获取）
4. 选择模型类型：**1) Claude（推荐）** / **2) OpenAI 格式** / **3) Gemini**，并可自定义模型 ID
5. 部署完成后，**可选配对**：在 Telegram 向 Bot 发送 `/start`，把 Bot 回复里的配对码输入脚本提示，即可完成私聊配对

## 支持的模型格式

| 类型 | API 格式 | 示例模型 |
|------|---------|---------|
| Claude 系列 | anthropic-messages | `claude-sonnet-4-6`、`claude-opus-4-6` |
| OpenAI 格式 | openai-completions | `gpt-4o`、`deepseek-chat`、`moonshot-v1-8k` |
| Gemini 系列 | google-generative-ai | `gemini-3-flash-preview` |

## 部署效果

### 终端部署过程

![部署终端截图](images/deploy-terminal.jpg)

### Telegram Bot 配对成功

![Telegram配对截图](images/telegram-pairing.jpg)

## 环境变量（可选）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `BREAKOUT_API_KEY` | Breakout API Key，预设则跳过交互 | - |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token，预设则跳过交互 | - |
| `BREAKOUT_MODEL_TYPE` | 模型类型，预设则跳过交互（`claude` / `openai` / `gemini`） | - |
| `BREAKOUT_MODEL_ID` | 模型 ID，预设则跳过交互 | - |
| `BREAKOUT_MODEL_NAME` | 模型显示名称（配合 `BREAKOUT_MODEL_ID` 使用） | 同 Model ID |
| `OPENCLAW_DATA_DIR` | 数据目录 | `/opt/openclaw` |
| `OPENCLAW_PORT` | 网关端口 | `18789` |

### 非交互式部署示例

```bash
# 全程无需手动输入，直接部署 Claude Sonnet 4.6
BREAKOUT_API_KEY=your_key \
TELEGRAM_BOT_TOKEN=your_bot_token \
BREAKOUT_MODEL_TYPE=claude \
sudo ./deploy.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `deploy.sh` | 一键部署脚本 |
| `images/` | README 配图 |

## 相关链接

- [Breakout](https://breakout.wenwen-ai.com) — AI API 网关
- [OpenClaw](https://github.com/openclaw/openclaw) — 开源 AI 助手框架

## License

MIT
