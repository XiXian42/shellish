# Issue 24 — `find all png files` 等"半命令半自然语言"输入无法拦截

**严重程度**: P3
**影响**: user 打 `find all png files` / `grep for the TODO` /
`rg in my code` 等"以已知命令开头的 NL 请求"时,hook 不拦截,
直接跑命令,失败。

## 位置

- `shell/profile.ps1` — `Test-ShellishShouldHandle` 函数
- `shell/bashrc.bash` — `command_not_found_handle`
- `shell/zshrc.zsh` — `command_not_found_handler`

## 现象

user 在 PS / bash / zsh 提示符打:

```
$ find all png files
$ grep for the TODO comments
$ rg in my code
```

**期望**: 路由到 shellish agent (语义上是自然语言)

**实际**:
- `find` / `grep` / `rg` 是真实存在的命令
- `Test-ShellishShouldHandle` 调 `Get-Command find` 找到 → 返回 false → 不拦
- bash `command_not_found_handle` 只在命令**找不到**时触发 → 不拦
- 真实命令跑 → `find: paths must precede expression: png` 报错
- 没法调 agent

## 根因

所有"hook-style"拦截都有同样的盲点: **第一 token 是已知命令时,hook 不知道这是命令还是 NL**。PS / bash / zsh 的 hook API 都**不**提供"命令存在但 user 想用 NL"的区分。

## 评估过的方案

### A. 改用 LLM 分类
- 在 hook 阶段,先调 LLM 判断"这是 NL 吗"
- ❌ 每次输入都多一次 LLM round-trip(慢且 token 成本)
- ❌ LLM 不总是对的(`git status` 可能被误判为 NL)

### B. 3+ token 一律走 shellish
- 简单规则: 多 token 倾向自然语言
- ❌ `rm -rf foo` (3 token) 走 shellish → 危险 (wrapper 会拦, 慢, 但至少安全)
- ❌ `git log --oneline` (4 token) 走 shellish → user 不爽(慢)

### C. 黑名单: 已知易混命令
- `find` / `grep` / `rg` / `awk` / `sed` 等放黑名单, 2+ token 一律走 shellish
- ❌ 维护成本(每次新加 user 习惯的命令就要更新)
- ❌ 黑名单外的"半命令"漏网
- ❌ `git push origin main` 第一 token `git` 不在黑名单 → 不走 shellish (OK), 但 `grep foo bar` 走 (OK)

### D. 试命令 + 失败兜底
- 先跑命令, exit != 0 时调 shellish
- ❌ 每个 NL 命令都先报错再重试(慢, 污染 stderr/output)
- ❌ `find all png` 跑 `find` → 报 `find: paths must precede expression: png` → 再调 shellish → user 看到双倍 noise

### E. 显式 prefix
- `shellish "find all png files"` 显式调
- ❌ user 不喜欢 (反馈)

## 实际影响

- `find.exe` 在 Windows 上**少见**: 默认 Win11 才有, Win10 需手动装
- 真撞这问题的 user 极少(命令/脚本用户更可能用 `shellish "..."` 显式 prefix)
- 真撞到时, work-around 简单: 用 `shellish "find all png files"`

## 决策

**不修**. 任何方案都让另一类输入变差. 当前行为是 trade-off 最优:
- 日常命令快速响应(不调 LLM)
- NL 输入(打错命令、多 token 中文、找不到的命令)走 shellish
- 半命令半 NL 走命令 + 失败(已知限制, work-around 是显式 prefix)

`lib/detect.sh` 的 LLM 分类逻辑**保留**作为未来基础, 但目前**不**接入任何 hook.

## 验收对照

- [x] `git status` / `ls -la` / `cd ..` 快速跑(不调 LLM)
- [x] `帮我压缩 png` / `fix this bug` / `deploy to prod` 走 shellish
- [x] `gti status` (typo) 走 shellish
- [x] `find all png files` 不走 shellish (已知限制)
