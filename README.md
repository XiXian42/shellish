# shellish

[English](#english) | [中文](#中文)

---

## English

Type natural language at your shell prompt — AI handles the rest.

```
$ compress all png files in this directory

$ fix the last git conflict

$ what's the weather in Beijing today
```

Typos are caught and corrected, never executed:

```
$ gti status
  did you mean:  git status
```

File deletions move to trash instead of running `rm` directly:

```
$ delete the build directory

  ⚠️  rm -rf build
  → will move to trash, not permanently delete

  [y] allow once  [a] allow all (this session)  [N] deny
```

### Install

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex
```

The installer will:
1. Detect available AI agents on your system (pi / omp / claude / codex)
2. Ask you to pick a default
3. Write the hook into your shell profile

Restart your shell to activate.

> **Prerequisite**: at least one supported AI agent must already be installed.

### Supported Agents

| Agent | Install |
|---|---|
| **pi** | `npm i -g @earendil-works/pi-coding-agent` |
| **omp** | `npm i -g @earendil-works/omp` |
| **Claude Code** | `npm i -g @anthropic-ai/claude-code` |
| **Codex CLI** | `npm i -g @openai/codex` |

shellish uses whatever is already on your system — it won't install agents for you.

### Usage

After installing the hook, just type at the prompt:

```bash
find all TODO comments in this repo and summarize them

deploy the app with production config

why is my build failing?
```

Or call explicitly:

```bash
shellish "clean up log files older than 7 days"
```

### Memory

shellish remembers personal facts you mention and carries them into future sessions:

```
$ remember I'm based in London and use neovim

  ⚙  bash  echo "- User is based in London" >> ~/.shellish/memory.md
  ⚙  bash  echo "- User uses neovim" >> ~/.shellish/memory.md
Got it.
```

Memory lives in `~/.shellish/memory.md` — edit it directly anytime.

### Commands

```bash
shellish config          # switch agent, configure delete behaviour
shellish status          # show current config and available agents
shellish install-hook    # manually install shell hook
shellish uninstall-hook  # remove shell hook
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.sh | bash
```

### How it works

```
shell prompt
  ↓
command_not_found_handler (zsh / bash)
  ↓
shellish --from-shell
  ↓
LLM classifies: typo → show correction  |  natural language → proceed
  ↓
build prompt (rules + memory + history + current time)
  ↓
call agent (pi / omp / claude / codex)
  ↓
stream-render output
  ↓
save to ~/.shellish/history/
```

On delete: `rm` is replaced by safe-rm which moves files to trash.  
macOS uses the `trash` CLI; Linux follows the freedesktop Trash spec.

### Platforms

| Platform | Status |
|---|---|
| macOS | ✅ |
| Linux | ✅ |
| Windows | ❌ not supported |

Shell: zsh / bash

---

## 中文

在终端里直接说话，AI 帮你干活。

```
$ 帮我把当前目录所有 png 压缩一下

$ fix the last git conflict

$ 查一下北京今天天气
```

打错命令时自动纠正，不执行：

```
$ gti status
  did you mean:  git status
```

删除文件时移入回收站，不会直接 rm：

```
$ 删除 build 目录

  ⚠️  rm -rf build
  → will move to trash, not permanently delete

  [y] allow once  [a] allow all (this session)  [N] deny
```

### 安装

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/install.sh | bash
```

**Windows（PowerShell）**
```powershell
irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex
```

安装过程会自动：
1. 检测系统上已有的 AI agent（pi / omp / claude / codex）
2. 让你选一个默认 agent
3. 把 hook 写入 shell 配置文件

重启终端后即可使用。

> **前提**：需要已安装至少一个支持的 AI agent。

### 支持的 Agent

| Agent | 安装 |
|---|---|
| **pi** | `npm i -g @earendil-works/pi-coding-agent` |
| **omp** | `npm i -g @earendil-works/omp` |
| **Claude Code** | `npm i -g @anthropic-ai/claude-code` |
| **Codex CLI** | `npm i -g @openai/codex` |

只使用系统上已有的 agent，shellish 不会帮你安装。

### 用法

安装 hook 后，直接在终端输入自然语言：

```bash
帮我找出当前目录最大的 10 个文件

find all TODO comments in this repo and summarize them

deploy the app, 用 production 配置
```

也可以显式调用：

```bash
shellish "把 logs 目录下 7 天前的文件都清理掉"
```

### Memory

shellish 会自动记住你说过的个人信息，下次对话自动带入：

```
$ 记住我在北京，用 vim

  ⚙  bash  echo "- 用户在北京" >> ~/.shellish/memory.md
  ⚙  bash  echo "- 用户使用 vim" >> ~/.shellish/memory.md
已记住。
```

memory 存在 `~/.shellish/memory.md`，可以直接编辑。

### 命令

```bash
shellish config          # 切换 agent，配置删除行为
shellish status          # 查看当前配置和可用 agent
shellish install-hook    # 手动安装 shell hook
shellish uninstall-hook  # 移除 shell hook
```

### 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.sh | bash
```

### 工作原理

```
终端输入
  ↓
command_not_found_handler (zsh / bash)
  ↓
shellish --from-shell
  ↓
LLM 判断：typo → 显示纠正  /  自然语言 → 继续
  ↓
构建 prompt（system rules + memory + 历史 + 当前时间）
  ↓
调用 agent（pi / omp / claude / codex）
  ↓
流式渲染输出
  ↓
保存历史到 ~/.shellish/history/
```

删除文件时：`rm` 被替换为 safe-rm，移入回收站而非直接删除。macOS 用 `trash` CLI，Linux 遵循 freedesktop Trash spec。

### 平台

| 平台 | 状态 |
|---|---|
| macOS | ✅ |
| Linux | ✅ |
| Windows | ❌ 暂不支持 |

Shell：zsh / bash

---

## License

MIT
