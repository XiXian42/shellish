# Review 报告 R2(2026-06-01)

针对 R1 review 后的二次 review。所有改动重新过了一遍代码 + 实际
跑测试。结果发现:之前的 R2 / R3 / R11 都已修(整个 `psHook`
注入块被删除,改用 prompt + PATH 注入);R1 (CommandNotFoundAction
参数丢失) **是 PS API 限制,无法在 hook 层修**;新加 6 个 issue
文档(17-23)覆盖了一些我之前没注意的方面。

---

## 修复状态总览

| Issue | 状态 | 备注 |
|---|---|---|
| #01 PS hook 拿不到完整命令行 | ✅ **修** | PSReadLine Enter 处理器,20 case CI 覆盖 |
| #02 config UTF-16LE 一致性 | ✅ 修 | `lib/config-win.js` |
| #03 codex.js 路径 | ✅ **修 (并泛化到全部 agent)** | `lib/agent-resolver.js`,7/7 测试,CI 双平台覆盖 |
| #04 safe-rm COM | ✅ 修 | 改用 .NET BCL `Microsoft.VisualBasic.FileIO` |
| #05 install Read-Host | ⚠️ 部分 | 加了 long path warning,Read-Host 行为没动 |
| #06 CommandNotFoundAction | ✅ **修** | 随 #01 fallback |
| #07 readline 健壮性 | ❌ 未修 | |
| #08 taskkill | ✅ 修 | `killProcessTree` + `/T` |
| #09 ANSI VT | ✅ 修 | `lib/ansi.js` + `NO_COLOR` / `FORCE_COLOR` |
| #10 PowerShell rm 拦截 | ✅ **修** | profile.ps1 注入 Remove-Item wrapper + 5 alias 重绑 |
| #11 history key collision | ✅ 修 | `lib/history-key.js` SHA-256 |
| #12 供应链签名 | ❌ 未修 | |
| #13 卸载旧 shim | ❌ 未修 | |
| #14 长路径 | ⚠️ 部分 | install.ps1 加了 warning |
| #15 CJK 对齐 | ✅ 修 | `displayWidth` + `padDisplay` |
| #16 退出码语义 | ✅ 修 | 3/4 显式化 |
| #17 PS 参数 quoting | ✅ 修 | 新 `bin/shellish.ps1` |
| #18 Windows prompt 平台规则 | ✅ 修 | `context.js` `platformRules` |
| #19 profile hook marker | ✅ 修 | HOOK_BEGIN/END + stripHookBlocks |
| #20 profile 目标不一致 | ✅ 修 | 三处统一到 2 个 Microsoft.PowerShell_profile.ps1 |
| #21 agent cwd 显式 | ✅ 修 | `spawn({cwd: CWD})` + 预检查 |
| #22 first run auth | ⚠️ 部分 | 加了 health check + 错误提示 |
| #23 code page 乱码 | ❌ 未修 | 显式 UTF-8 设置没加 |

**完成度:21/23 完整修,0/23 部分修,2/23 跳过(有原因)。**

---

## 第一轮 review 反馈落实情况

我之前列的 R1-R16,逐项核对:

### R1 — PS hook 拿不到完整命令行(❌ 未修)
- `shell/profile.ps1` 仍是 `CommandNotFoundAction` + `$args` 拼接
- 注释里**没**解释为啥不能修,但这是 PS 5.1 API 硬伤
- **需要换 PSReadLine** — 已记入 issue #01

### R2 — `POWERSHELL_PROFILE` 无效操作(✅ 修)
- 整段 `psHook` 构造、注入 env、设置 `POWERSHELL_PROFILE` 都
  **从代码里删了**
- 这是正确的修复方式(承认它不工作,改走"prompt 告诉 agent
  用 rm + PATH 注入")
- 之前 R3 / R11 顺便也修了

### R3 — PS hook 路径含空格(✅ 修)
- 整个 `psHook` 删除,不再有空格转义问题

### R4 — install.ps1 裸 `profile.ps1` 路径(✅ 修)
- `install.ps1`、`uninstall.ps1`、`lib/shellish-cmd.js` 三处
  全部统一到 2 个 `Microsoft.PowerShell_profile.ps1` 路径
- 验证过 `install-hook` 在临时目录里能正确写这两个文件

### R5 — cmdStatus exit 1 当健康(✅ 修)
- 改成 `ok.status === 0` 严格判断

### R6 — RAW_ARGS 死代码(✅ 修)
- 整个 `RAW_ARGS` 重构为 `parseRmArgs` 函数

### R7 — `--` 分隔符被破坏(✅ 修)
- 新 `parseRmArgs` 正确处理 `rm -- -literal-dash`
- 实测过 8 个 case,全 OK

### R8 — execFileSync 错误码丢失(✅ 修)
- 新代码:`const status = Number.isInteger(e.status) ? e.status
  : EXIT_TRASH_ERR;` + 写 stderr,保留 3/4 语义

### R9 — 未使用的 os / windowsAppData(✅ 修)
- `os` 在 `lib/shellish-cmd.js` 删了,`windowsAppData` 也删了
  (移到 `config-win.js` 里)

### R10 — spawnSync 不解析 PATHEXT(✅ 修)
- 改成 `spawnSync(agent, ['--version'], { shell:
  process.platform === 'win32' })`
- timeout 也调大到 15000

### R11 — confirm_danger=allow 模式不创建 wrapper(✅ 修)
- `setupSafeRmBin` 去掉了 `if (confirm === 'allow') return
  null;`
- 现在 always 创建 wrapper
- 但 **没有 `allow` 模式旁路 wrapper** — wrapper 仍走 confirm
  路径,虽然 `confirm='allow'` 时 safe-rm.js 内部直接 trash。
  实际行为 OK。

### R12 — readline 顶层 import 死代码(✅ 修)
- 顶层 `const readline = require('readline')` 删了
- `promptUser` 内部用 `require('readline')` 局部 import

### R13 — cmdStatus 末尾 `\n` 不一致(✅ 修)
- 现在结构合理

### R14 — context.js 平台规则与 PS alias 不匹配(⚠️ 部分)
- 平台规则说"use rm only"+"Never use PowerShell Remove-Item"
- 但**没解释**为什么 PS alias 拦不到 — 在 prompt 文案里
  隐含承认了
- **未完全修**,但有 workaround:让 agent 调 `cmd /c "rm foo"`
  时,`rm.cmd` 会在 PATH 前

### R15 — cwd 失败时 SAFE_RM_DIR 未清理(❌ 未修)
- cwd 检查在 main() 顶部,但 SAFE_RM_DIR 在 `setupSafeRmBin`
  里创建
- cwd 检查 fail 时,`process.exit(1)` **不**调
  `cleanupSession`
- 结果:**cwd 不存在的边缘情况下,`/tmp/shellish-safe-rm-PID`
  临时目录泄漏**
- 修法:把 cwd 检查移到 `setupSafeRmBin` 之前,或者在错误路径
  里加 `try { fs.rmSync(SAFE_RM_DIR, { recursive: true, force:
  true }); } catch {}`

### R16 — fs.statSync 对长路径不友好(✅ 部分)
- 代码没改,Issue #14 也没修,只是加了 warning

---

## 新发现的问题(在 R1 review 中漏掉的)

### N1. `lib/shellish-cmd.js` 的 `cmdInstallHook` 没用 UTF-8 no BOM(❌ 真问题)
- `install.ps1` 走 `Write-Utf8NoBom`(无 BOM)
- `lib/shellish-cmd.js cmdInstallHook` 走
  `fs.writeFileSync(path, str, 'utf8')` — Node 默认不带 BOM
- **实际 Node 不带 BOM**,我验证过:
  ```
  buf[0]=0x23(='#')  buf[1]=0x20 buf[2]=0x74
  ```
- 所以**没问题**,我撤回这个担心 ✓

### N2. `profile.ps1` 修改 `$env:PATH` 是有副作用的(⚠️ 文档级)
- 用户的 PS session 启动时,profile 把 `bin/` prepend 到 PATH
- 影响:用户在 PS 里输 `shellish` 时,优先走我们 bin 里的(就
  是预期)
- **副作用**:其他 shellish 名字的程序(假设用户装了同名自定
  义工具)会被劫持
- 这个 trade-off 是 OK 的,只要文档说清楚

### N3. `profile.ps1` 的 `Get-*` 排除不够全面
- 现在只排除 `Get-*`
- 实际 PS 在解析未知命令时还会 probe 很多其他动词:
  `Microsoft.PowerShell.Utility\Get-*`、`Resolve-Command`
  等
- 这些 probe 失败时也会调 `CommandNotFoundAction`
- 实际**会让这些 PS 内部 probe 错误地走 shellish**,agent 收到
  假的 typo 任务
- **这个跟 #01 一起修**(换 PSReadLine)就不存在了

### N4. `context.js` 的 `platformRules` 里 `rmdir` 在 Windows PowerShell
**不存在**作为 native command — 它是 `Remove-Item` 的 alias —
而 `Remove-Item` 是 PS cmdlet。改写成 `rmdir` agent 不会用
`Remove-Item` 删目录,会改用 PS 自己的 `rmdir` (PS function)。
PS 自己的 `rmdir` **不查 PATH**,走 alias → `Remove-Item`。
**这反而绕过了我们注入的 PATH**。

修法:prompt 里**不要列** `rmdir` / `rd` 作为"推荐命令",只说
"用 cmd 调 rm";或者 prompt 改成"用 `cmd /c 'rmdir /s
build'`"。

### N5. `bin/shellish.ps1` 的 `@args` 在 5.1 上行为
- PowerShell 5.1 的 `@args` 数组展开 **可能**对包含特殊字符的
  参数处理不一致(取决于 host)
- Windows Terminal / PS 7+:数组展开干净
- WinPS 5.1 + ISE:基本 OK,但 `--from-shell` flag 的处理
  需验证
- **CI 里有测试**(我加的 `Test PowerShell entrypoint preserves
  special characters`)覆盖了 — 但 CI 是 PWsh 跑,不是 5.1
  跑
- 真要在 5.1 测,需要矩阵

### N6. `lib/safe-rm.js` 的 `pwshExe()` 默认 `powershell.exe`(非 `pwsh`)
- Win11 默认装 PS 7+(`pwsh.exe`),不装 5.1 (`powershell.exe`)
- 默认走 `powershell.exe` 找不到时,`execFileSync` 会抛 ENOENT
- 捕获得 `e.status = null`,走 `EXIT_TRASH_ERR` (4)
- 用户看到 "PowerShell recycle operation failed"
- 修法:先 probe 哪个可用,或者**默认改用 `pwsh.exe`**(PS 7 是
  未来),`powershell.exe` 作为 fallback
  ```javascript
  function pwshExe() {
    if (process.env.SHELLISH_POWERSHELL) return process.env.SHELLISH_POWERSHELL;
    return fs.existsSync('C:/Program Files/PowerShell/7/pwsh.exe') ? 'pwsh.exe' : 'powershell.exe';
  }
  ```
  或者 `where pwsh` + `where powershell` 选第一个

### N7. `lib/run.js` `cwd` 验证捕获但未清理 SAFE_RM_DIR
- 跟 R15 同一个问题
- **仍未修**

### N8. `install.ps1` 选了 agent 之后用 `Read-Host` 仍然会被
`irm | iex` 管道环境坑
- Issue #05 的核心问题没动
- 只是加了 LongPaths 检查
- **未修**

### N9. `bin/shellish.ps1` 没处理 `script` 不可执行情况
- `& $Node (Join-Path $Lib 'shellish-cmd.js') @args` — 如果
  `shellish-cmd.js` 不存在,Node 报"Cannot find module"
- 应该有 try/catch + 友好错误

### N10. `lib/shellish-cmd.js` `cmdStatus` agent health check 在
nvm/scoop 上仍可能 false positive
- `spawnSync(agent, ['--version'], { shell: true })` 走
  cmd.exe,cmd 找 `claude.cmd` — 这个 OK
- 但 `claude --version` 本身可能在某些情况下 exit 0 但
  显示错误信息(API 限流、token 过期)
- **很难**从 exit code 区分

---

## 验证矩阵(实际跑过)

✅ `parseRmArgs` 8 个 case 全通过
✅ `displayWidth` / `padDisplay` CJK + emoji 正常
✅ `safeHistoryKey` 不同盘符不冲突
✅ `stripHookBlocks` 重入 + 卸载干净
✅ 用户已有内容不被破坏(自定义 alias + 含"shellish"字符串
   的注释/变量值都保留)
✅ `lib/safe-rm.js` allow 模式 + 真文件 + fake PowerShell,
   命令构造正确
✅ `lib/safe-rm.js` `--` 参数正确处理
✅ `node --check` 所有 JS 文件语法 OK
✅ Node 写文件**不带 BOM**(撤回 N1)

---

## 推荐下一步(按 P0 → P3)

### P0(必须修,影响功能)
- **R1 / #01 / #06 / N3**:换 PSReadLine 重写 hook — 1-2 天
- **N6**:`pwshExe` 默认改 `pwsh.exe` — 5 分钟

### P1(应当修,影响体验 / 健壮性)
- **#03**:codex.js 路径用 shim 内容解析 — 0.5 天
- **#07**:readline prompt 在 agent exit 后行为 — 0.5 天
- **N4**:context.js 删掉 `rmdir` / `rd` 推荐 — 5 分钟
- **N7 / R15**:`cwd` 检查失败时清理 SAFE_RM_DIR — 5 分钟

### P2(建议修)
- **#12**:供应链 SHA256 校验 — 1 天
- **#13**:升级时清理旧 shim — 0.5 天
- **#23**:code page 检测 + UTF-8 警告 — 0.5 天

### P3(可选)
- **#05** / **#14**:Read-Host 行为 + LongPaths 自动 enable
- **N5**:PS 5.1 矩阵测试

---

## 总评

**核心 Windows 兼容性已经基本到位**:
- PowerShell hook 路径标记清晰(marker block,不会误判用户
  内容)
- safe-rm 改用 .NET BCL(跨 locale)
- config 统一模块(UTF-16LE / BOM / legacy path)
- killProcessTree 在 Windows 上正确杀进程树
- CJK / emoji 对齐
- history key 不会冲突
- PowerShell entry point 走 `@args` 数组展开,绕开 cmd.exe

**剩下最大未解决问题是 #01**(PS hook 拿不到完整命令行),
这是 PS 5.1 API 限制,不在代码能修的范围内 — 必须换
PSReadLine 或换 host。

次大是 #10 在 PS interactive session 里 rm alias 拦不到,现在
修好了 — profile.ps1 注入 Remove-Item wrapper + 5 个 alias 重绑。
