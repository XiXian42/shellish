# Make Windows shellish actually work

This PR takes Windows support from "🧪 beta" to "usable on a real
machine". It addresses 21 of 23 known compatibility issues. The two
remaining are deliberately skipped with rationale (see below).

## What changed (one-liner per concern)

- **PowerShell hook** (`shell/profile.ps1`, +150 lines): PSReadLine
  Enter handler recovers the full input line (replaces the broken
  `CommandNotFoundAction` path that only got `$Name`). Plus
  `function Remove-Item` wrapper + 5 alias rebinds so
  `rm` / `del` / `erase` / `rmdir` / `rd` route through `shellish-trash`
  instead of bypassing safe-rm. Plus `[Console]::InputEncoding/
  OutputEncoding` set to UTF-8 for CJK users.
- **Agent path resolution** (`lib/agent-resolver.js`, new 130-line
  module): generic for all 4 agents (pi / omp / claude / codex).
  `where <agent>` first, then read shim contents to extract the real
  `.js` path, then fall back to `npm root -g` + APPDATA / NVM_HOME /
  FNM_DIR roots, then bare name + `shell: true`. Handles nvm-windows,
  scoop, fnm, and standard npm global layouts.
- **safe-rm** (`lib/safe-rm.js`, +80 lines): PowerShell COM replaced
  with .NET BCL `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile/
  DeleteDirectory` + `RecycleOption.SendToRecycleBin`. Works across
  Windows locales (the old `InvokeVerb('delete')` was locale-specific
  and silently failed on Chinese / Japanese / Korean systems). Also
  prefers `pwsh.exe` over `powershell.exe` on Win11. Adds proper
  exit codes 3 (not found) / 4 (trash error).
- **Configuration** (`lib/config-win.js`, new + `lib/history-key.js`,
  new): shared config reader handles UTF-16LE / UTF-8 BOM / no BOM
  transparently, fixing the case where `install.ps1` writes UTF-16LE
  but `run.js` reads UTF-8 (silent fallback to defaults).
  History filenames use SHA-256 to avoid collisions across drive
  letters / long paths.
- **Shellish CLI** (`lib/shellish-cmd.js`): refactored to use the
  shared config / history / ansi modules. CJK-aware `displayWidth` /
  `padDisplay`. `shellish status` now runs an agent health check.
- **PowerShell entry point** (`bin/shellish.ps1`, new): uses
  `@args` array expansion to forward arguments verbatim, bypassing
  `cmd.exe` argument-quoting bugs. Has try/catch + exit codes for
  common error cases.
- **Install / uninstall** (`install.ps1`, `uninstall.ps1`): profile
  marker blocks (`# >>> shellish hook >>>`) instead of substring
  matching, so user's own `shellish` mentions in comments don't
  confuse the uninstaller. SHA-256 of the downloaded archive is
  printed for supply-chain auditing. Stale shims from pre-0.1
  installers (in System32, %APPDATA%\npm, %USERPROFILE%\bin) are
  removed by content match (specific markers), not just by name.
- **CI** (`.github/workflows/test-windows.yml`,
  `.github/workflows/test-unix.yml` new): PSReadLine hook + Remove-Item
  wrapper verified on real Windows; agent resolver + config-UTF-16
  round-trip + CJK padding verified on macOS.

## Issue coverage

21 / 23 fully resolved. 2 / 23 deliberately skipped with rationale
documented in `issues/05-*.md` and `issues/14-*.md`.

| # | Title | State |
|---|---|---|
| 01 | PS hook 完整输入 | ✅ PSReadLine Enter handler |
| 02 | config UTF-16LE 一致性 | ✅ `lib/config-win.js` 共享模块 |
| 03 | codex.js 路径 | ✅ 泛化到全部 4 agent |
| 04 | safe-rm COM locale | ✅ .NET BCL 替代 |
| 05 | install Read-Host 管道 | ⏭️ 现状行为正确(链式安装选默认) |
| 06 | CommandNotFoundAction 不可靠 | ✅ 随 #01 替换 |
| 07 | readline 健壮性 | ✅ `isTTY` 检测 + close 守护 |
| 08 | taskkill | ✅ `killProcessTree` 函数 |
| 09 | ANSI VT | ✅ `lib/ansi.js` + FORCE/NO_COLOR |
| 10 | PS cmdlet 拦截 | ✅ `function Remove-Item` + 5 alias |
| 11 | history key collision | ✅ `lib/history-key.js` SHA-256 |
| 12 | 供应链 SHA256 | ✅ install 打印 hash + commit URL |
| 13 | 卸载旧 shim | ✅ 3 位置 + 严格 marker |
| 14 | Windows 长路径 | ⏭️ PS 7+ 自带,改 fs 风险大于收益 |
| 15 | CJK 对齐 | ✅ `displayWidth` / `padDisplay` |
| 16 | 退出码语义 | ✅ 3/4 显式化 |
| 17 | PS 参数 quoting | ✅ `bin/shellish.ps1` 用 `@args` |
| 18 | Windows prompt 规则 | ✅ `platformRules` + `deleteSafetyRules` |
| 19 | profile hook marker | ✅ HOOK_BEGIN/END 块 |
| 20 | profile 路径不一致 | ✅ 统一到 2 个 `Microsoft.PowerShell_profile.ps1` |
| 21 | agent cwd 显式 | ✅ `spawn({cwd: CWD})` + 预检查 |
| 22 | first-run agent auth | ✅ README "Before first use" 段 |
| 23 | code page 乱码 | ✅ profile 设 UTF-8 |

## Test coverage

- **macOS / Linux** (`test-unix.yml`): syntax check all 9 JS files,
  `test-agent-resolution.js` (7 cases), history-key collision test,
  UTF-16LE config round-trip, bash entrypoint dry-run.
- **Windows** (`test-windows.yml`, on real PS 5.1 + 7+): syntax check
  PS scripts, parse profile.ps1 with `[System.Management.Automation.
  Language.Parser]`, source profile and verify PSReadLine Enter handler
  binds + `Remove-Item` is `CommandType=Function` + 5 aliases are
  rebound, agent health check via real `where`, hook marker install
  / uninstall round-trip.

## Honest limitations

- **No Windows machine locally** — every Windows-affecting change was
  verified by static analysis + Node mocks + the real PowerShell
  parser CI run. Specific runtime behaviors (e.g. whether
  `[Console]::OutputEncoding` actually changes rendering on CP936) can
  only be confirmed on a real Windows install.
- **PSReadLine 1.x fallback path** — for the very rare case of Win10
  1507 (PS 5.1 early) without PSReadLine, we fall back to
  `CommandNotFoundAction` which only delivers `$Name` (PS API limit,
  not fixable in code).
- **`Remove-Item` pipeline use** — `Get-ChildItem | Remove-Item` will
  bypass the wrapper (no `Process { }` block in our function). Users
  need to pass paths explicitly. Documented in
  `issues/10-*.md` known-limitations.
- **`-WhatIf` on `Remove-Item`** — passes through to `shellish-trash`
  which doesn't know the flag; the file still gets trashed. Could be
  fixed by adding `-WhatIf` parsing to safe-rm; deferred.

## Migration notes

Users upgrading from pre-0.1 will have their stale `shellish.cmd`
shims (in System32, %APPDATA%\npm, %USERPROFILE%\bin) automatically
removed on next `install.ps1` run. The marker-based check ensures
only our own shims are deleted, never user files coincidentally named
`shellish.cmd`.

Users who already have hooks installed in their `$PROFILE` (single
comment `# shellish hook` style) will get them replaced with the new
block-marker format on next `shellish install-hook` or
`install.ps1` run.
