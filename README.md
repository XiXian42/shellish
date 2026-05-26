# shellish

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

---

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/axlewis/shellish/main/install.sh | bash
```

安装过程会自动：
1. 检测系统上已有的 AI agent（pi / omp / claude / codex）
2. 让你选一个默认 agent
3. 把 hook 写入 `~/.zshrc` 或 `~/.bashrc`

重启终端或 `source ~/.zshrc` 后即可使用。

> **前提**：需要已安装至少一个支持的 AI agent。

---

## 支持的 Agent

| Agent | 安装 |
|---|---|
| **pi** | `npm i -g @earendil-works/pi-coding-agent` |
| **omp** | `npm i -g @earendil-works/omp` |
| **Claude Code** | `npm i -g @anthropic-ai/claude-code` |
| **Codex CLI** | `npm i -g @openai/codex` |

只使用系统上已有的 agent，shellish 不会帮你安装。

---

## 用法

安装 hook 后，直接在终端输入自然语言：

```bash
# 中文
帮我找出当前目录最大的 10 个文件

# English
find all TODO comments in this repo and summarize them

# 混合
deploy the app, 用 production 配置
```

也可以显式调用：

```bash
shellish "把 logs 目录下 7 天前的文件都清理掉"
```

---

## Memory

shellish 会自动记住你说过的个人信息，下次对话自动带入：

```
$ 记住我在北京，用 vim

  ⚙  bash  echo "- 用户在北京" >> ~/.shellish/memory.md
  ⚙  bash  echo "- 用户使用 vim" >> ~/.shellish/memory.md
已记住。
```

memory 存在 `~/.shellish/memory.md`，可以直接编辑。

---

## 命令

```bash
shellish config          # 切换 agent，配置删除行为
shellish status          # 查看当前配置和可用 agent
shellish install-hook    # 手动安装 shell hook
shellish uninstall-hook  # 移除 shell hook
```

---

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/axlewis/shellish/main/uninstall.sh | bash
```

---

## 工作原理

```
终端输入
  ↓
zsh command_not_found_handler
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

---

## 平台

| 平台 | 状态 |
|---|---|
| macOS | ✅ |
| Linux | ✅ |
| Windows | ❌ 暂不支持 |

Shell：zsh / bash

---

## License

MIT
