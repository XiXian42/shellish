# Issue 03 — Windows codex.js 路径解析在 nvm/scoop 下失败

**严重程度**: P1
**影响**: 用 nvm-windows / scoop / fnm 装 Node 的用户在 Windows
下无法调用 codex agent

## 位置

- `lib/run.js` — `findWindowsCodexJs()`
- `lib/run.js` — `agentCmd()` 的 `case 'codex'`

## 现象

`findWindowsCodexJs()` 的三个查找分支:

1. 遍历 `env.PATH` 每个目录,拼 `node_modules/@openai/codex/bin/codex.js`
2. `npm root -g` 输出
3. `where codex` 输出所在目录再拼 `node_modules/...`

都有问题:
- nvm-windows 把全局 `node_modules` 放在 `%NVM_HOME%\vXX.X.X\node_modules\`,
  不在 PATH 的某个子目录里(虽然 `current` 在 PATH,但 `node_modules`
  与 `node.exe` 平级)
- scoop 的 Node 安装在 `%USERPROFILE%\scoop\apps\nodejs\current\`
- fnm 用 `%FNM_DIR%\node-versions\...`
- 第二个分支 `npm root -g` 受 `npm config get prefix` 影响,nvm
  下经常返回错路径
- 第三个分支 `where codex` 可能返回多个结果(用户 PATH 里多份
  codex),逻辑随机选

## 修复方向

最稳的方法是**读 `codex.cmd` shim 内容**。npm 装全局包时生成的
`codex.cmd` 形如:

```bat
@ECHO off
SETLOCAL
CALL :find_dp0

IF EXIST "%dp0%\node_modules\@openai\codex\bin\codex.js" (
  SET "_prog=%dp0%\node_modules\@openai\codex\bin\codex.js"
) ELSE ...
```

解析 shim,提取 `codex.js` 的绝对路径,优先用这个结果。

## 验收标准

- [ ] nvm-windows + 全局 codex 安装:能正确找到 codex.js
- [ ] scoop + 全局 codex:能正确找到
- [ ] fnm + 全局 codex:能正确找到
- [ ] 多份 codex 在 PATH 时,选 PATH 第一个
- [ ] 不存在 codex 时,降级到原行为(`cmd: 'codex'` + `PATH`
      查找,而不是直接报错)

## 状态

✅ 修 (2026-06-01) — 抽到独立模块 `lib/agent-resolver.js`,
适用于全部 4 个 agent,不只是 codex:

- `resolveAgentCommand(agent, env)` 返回 `{ cmd, args, displayCmd, shell }`
- 4 层 fallback: `where <agent>` → 读 shim 提取 `.js` → npm global
  layout (npm root / APPDATA / NVM_HOME / FNM_DIR) → bare name +
  `shell: true`
- shim 解析 3 种形式: `SET "_prog=..."` (quoted), `SET _prog=...`
  (unquoted), `node "..."`
- 所有 agent (pi / omp / claude / codex) 都加 `shell: true` on
  Windows → PATHEXT 解析
- claude 走 fallback 因为它 ship .exe, 不是 .js
- 7/7 unit test 覆盖 (darwin / win32 / nvm / fnm / appdata / claude
  fallback)
- CI: macOS 跑 `scripts/test-agent-resolution.js`, Windows 跑真实
  `where` 探测

## 验收对照

- [x] nvm-windows + 全局 codex: APPDATA + NVM_HOME 探测
- [x] scoop + 全局 codex: APPDATA 探测
- [x] fnm + 全局 codex: FNM_DIR 探测
- [x] 多份 codex: `where` 返回 PATH 顺序,选第一个非 WindowsApps
- [x] 不存在 codex: 走 fallback,shell: true, cmd 仍是 agent name
- [x] pi/omp/claude 同样受益(同一个函数)
