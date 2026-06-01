# Issue 18 — prompt 不应硬编码 Windows PowerShell 命令策略

**严重程度**: P1
**影响**: 过度规定 Windows/PowerShell 命令会干扰 Claude Code / Codex / pi 根据自身 tool shell 自动选择可用命令。

## 位置

- `lib/context.js` — `buildPrompt()` 的平台规则
- `lib/run.js` — safe-delete command PATH 注入

## 背景

最初的问题是:Windows 下 agent 可能生成 Unix/Linux 命令,例如
`grep` / `find` / `ls -la`,在干净 PowerShell 环境里失败。早期修复
方向是在 prompt 中明确写:

```text
You are running on Windows PowerShell.
Prefer PowerShell-native commands.
Use Get-ChildItem instead of Unix find/ls.
Use Select-String instead of grep.
```

但这个方向有副作用:

1. Claude Code / Codex / pi 自己通常知道 tool 的执行 shell,并能根据
   命令失败结果自适应。
2. shellish 的 Node 进程在 Windows 上运行,不代表 agent tool 一定在
   PowerShell 里运行；可能是 cmd.exe、Git Bash、WSL、agent 自己的
   sandbox shell 或其它 executor。
3. 把 shell 教程写进 shellish prompt 会降低 agent 自主选择最佳命令的
   能力。
4. 删除安全和 shell 兼容是两件事,不应该混在一个 PowerShell 规则里。

## 修复方向

prompt 只提供平台事实和安全边界,不教 agent 具体 shell 命令替换:

```text
- Host OS: Windows.
- Use commands appropriate for the execution shell/tools available to you. If a command is unavailable or has incompatible syntax, adapt based on the observed error.
```

删除安全单独处理:

```text
- File deletion safety: do not permanently delete files.
- When deleting files or directories, prefer the explicit safe-delete command: shellish-trash <path>.
- If shellish-trash is unavailable, use bare rm so shellish can intercept it where supported.
- Do not intentionally bypass shellish's safe-delete mechanism with absolute command paths or direct filesystem APIs.
```

同时 `run.js` 在 agent session PATH 中注入:

- Windows: `shellish-trash.cmd`, `shellish-rm.cmd`, `rm.cmd`, `del.cmd`, `erase.cmd`, `rmdir.cmd`, `rd.cmd`
- Unix/macOS: `shellish-trash`, `shellish-rm`, `rm`

安装目录也提供显式入口:

- `bin/shellish-trash`, `bin/shellish-rm`
- `bin/shellish-trash.cmd`, `bin/shellish-rm.cmd`

## 验收标准

- [x] Windows 下 `context.js build` 输出包含 `Host OS: Windows`
- [x] prompt 不再包含 `Get-ChildItem instead` / `Select-String instead` 这类 PowerShell 命令替换规则
- [x] prompt 包含 `shellish-trash` safe-delete 规则
- [x] macOS/Linux 下也包含 shell-agnostic host OS 事实
- [x] `run.js` 注入 `shellish-trash` / `shellish-rm` wrappers
- [x] CI 覆盖 prompt substring 检查

## 状态

✅ 修 (2026-06-01) — 已从“Windows PowerShell 命令教学”改为
shell-agnostic prompt + 显式 `shellish-trash` 删除安全边界。

## 已知限制

- prompt 不能强制 agent 一定使用 `shellish-trash`;它是安全边界提示,
  不是执行层强制拦截。
- `cmd.exe` 内置 `del` / `rmdir` / `rd` 不一定被 PATH wrapper 拦截,
  因此推荐 agent 使用 `shellish-trash` 或 bare external `rm`。
- PowerShell alias/cmdlet 删除另由 Issue #10 的 profile wrapper 缓解。
