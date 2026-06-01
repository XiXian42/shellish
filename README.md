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

**Windows (PowerShell, beta)**
```powershell
irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex
```

Use PowerShell 7 or Windows PowerShell 5.1 as the main Windows entry point. `shellish.cmd` exists as a compatibility shim, but PowerShell (`shellish.ps1`) preserves complex arguments, Unicode, and shell hooks more reliably than CMD.

If PowerShell blocks the hook with "running scripts is disabled", enable user scripts once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

If your Windows home directory is restricted, set a writable data directory before running shellish:

```powershell
$env:SHELLISH_HOME = "$env:APPDATA\shellish"
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

> **Before first use**: complete login / authentication for your agent **outside of shellish** (e.g. run `claude` once and finish the browser OAuth flow, or `codex login`). shellish's `agent health` check in `shellish status` will surface this; an un-authenticated agent fails with a confusing error if you skip this step.

### Usage

After installing the hook, just type natural language at the prompt:

```bash
compress all png files in this directory

fix the last git conflict

deploy the app with production config

why is my build failing?
```

If a request happens to start with a word that is also a real shell command, your shell may run that command instead of handing the line to shellish. In those rare command-name conflicts, wrap the sentence in quotes so the shell treats it as one unknown command and shellish can handle it:

```bash
"find all TODO comments in this repo and summarize them"
"sort these files by size and summarize the largest ones"
```

You can still call `shellish "..."` explicitly if you prefer.

### Memory

shellish remembers personal facts you mention and carries them into future sessions:

```
$ remember I'm based in London and use neovim

  ⚙  bash  echo "- User is based in London" >> ~/.shellish/memory.md
  ⚙  bash  echo "- User uses neovim" >> ~/.shellish/memory.md
Got it.
```

Memory lives in `~/.shellish/memory.md` on macOS/Linux and `%APPDATA%\shellish\memory.md` on Windows. You can override it with `SHELLISH_HOME`.

### Commands

```bash
shellish config          # switch agent, configure delete behaviour
shellish status          # show current config and available agents
shellish install-hook    # manually install shell hook
shellish uninstall-hook  # remove shell hook
```

### Uninstall

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.ps1 | iex
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
save to shellish data history/ (`~/.shellish` or `%APPDATA%\shellish`)
```

On delete: `rm` is replaced by safe-rm which moves files to trash.  
macOS uses the `trash` CLI; Linux follows the freedesktop Trash spec.

### Platforms

| Platform | Status |
|---|---|
| macOS | ✅ |
| Linux | ✅ |
| Windows | 🧪 beta |

Shell: zsh / bash / PowerShell

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

**Windows（PowerShell，beta）**
```powershell
irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex
```

Windows 建议使用 PowerShell 7 或 Windows PowerShell 5.1 作为主入口。`shellish.cmd` 只是兼容 shim；PowerShell 入口（`shellish.ps1`）对复杂参数、Unicode 和 hook 更可靠。

如果 PowerShell 提示 `running scripts is disabled`，需要为当前用户开启脚本执行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

如果 Windows 用户目录受限，可以先指定一个可写的数据目录：

```powershell
$env:SHELLISH_HOME = "$env:APPDATA\shellish"
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

fix the last git conflict

deploy the app, 用 production 配置

why is my build failing?
```

如果某个请求刚好以真实 shell 命令名开头，shell 可能会直接执行该命令，而不是交给 shellish。遇到这类少数命令名冲突时，推荐把整句话用引号包起来，让 shell 把它当成一个未知命令交给 shellish：

```bash
"find all TODO comments in this repo and summarize them"
"sort these files by size and summarize the largest ones"
```

如果你更喜欢，也仍然可以显式调用 `shellish "..."`。

### Memory

shellish 会自动记住你说过的个人信息，下次对话自动带入：

```
$ 记住我在北京，用 vim

  ⚙  bash  echo "- 用户在北京" >> ~/.shellish/memory.md
  ⚙  bash  echo "- 用户使用 vim" >> ~/.shellish/memory.md
已记住。
```

memory 在 macOS/Linux 存在 `~/.shellish/memory.md`，Windows 存在 `%APPDATA%\shellish\memory.md`。也可以用 `SHELLISH_HOME` 指定位置。

### 命令

```bash
shellish config          # 切换 agent，配置删除行为
shellish status          # 查看当前配置和可用 agent
shellish install-hook    # 手动安装 shell hook
shellish uninstall-hook  # 移除 shell hook
```

### 卸载

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.sh | bash
```

**Windows（PowerShell）**
```powershell
irm https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.ps1 | iex
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
保存历史到 shellish 数据目录 history/（`~/.shellish` 或 `%APPDATA%\shellish`）
```

删除文件时：`rm` 被替换为 safe-rm，移入回收站而非直接删除。macOS 用 `trash` CLI，Linux 遵循 freedesktop Trash spec。

### 平台

| 平台 | 状态 |
|---|---|
| macOS | ✅ |
| Linux | ✅ |
| Windows | 🧪 beta |

Shell：zsh / bash / PowerShell

---

## License

MIT
