# Issue 10 — safe-rm 拦截不到 PowerShell 的 `rm` / `del` / `Remove-Item`

**严重程度**: P1
**影响**: agent 在 PowerShell 下用 `del` / `Remove-Item` 删文件时
**完全绕过** safe-rm,直接删除

## 位置

- `lib/run.js` — `setupSafeRmBin()`, `agentCmd()` PATH 注入
- `lib/safe-rm.js`

## 现象

`run.js` 把 `SAFE_RM_DIR` prepend 到 `PATH`,但:

1. **PowerShell 里 `rm` 是 `Remove-Item` 的 alias**,由 PS 引擎
   自己解析,根本不查 PATH
2. **`del` 也是 alias**,同理
3. **agent 在 PS 下倾向用 PowerShell 原生命令**,而不是 `rm`:
   - Claude/Codex 在 PS 7 下常输出 `Remove-Item -Recurse -Force ...`
   - 用 `cmd /c "rm -rf ..."` 时也常常 wrap 成
     `Remove-Item`
4. `where rm` 在 PS 7 上返回 **PowerShell alias**,不返回 PATH 里
   的 `rm.cmd` shim

## 后果

- safe-rm 几乎在 PowerShell 7+ 上**完全失效**
- agent 删文件直接走 `Remove-Item`,**不进回收站,不弹确认**
- 用户在 `shellish config` 里设的 `confirm_danger=ask` 形同虚设

## 修复方向

不依赖 PATH 注入,改用 PowerShell 自己的拦截机制:

```powershell
# 在 profile.ps1 里
Set-Alias -Name rm -Value Remove-Item -Scope Global -Force
Remove-Item alias:del
function global:Remove-Item {
    # 弹 shellish 确认,然后转去真 Remove-Item / safe-rm
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(...)
    ...
}
```

但这会和 PS 引擎深度耦合。更简单的方案是 **agent prompt 注入**:
- 在 `context.js` 拼 prompt 时,显式告诉 agent:
  - "Use `rm` exclusively; never use `Remove-Item` or `del`"
  - "rm is intercepted by shellish"
- 在 PS 5.1 上保留 PATH 注入
- 在 PS 7+ 强制走 PowerShell function 拦截

最干净的方案是用 PS 函数 + `function Remove-Item { ... }` 包装。

## 验收标准

- [ ] agent 在 PS 7+ 用 `Remove-Item -Recurse foo` 触发 safe-rm
      确认
- [ ] agent 用 `del foo` 同样拦截
- [ ] 用户的 `y` 答正确生效
- [ ] agent 用 `cmd /c "rm -rf foo"` 也拦截(走 PATH)

## 状态

⚠️ 部分修 (2026-06-01,2026-06-11 回归后恢复) — 在
`shell/profile.ps1` 注入 PS cmdlet/alias 拦截。交互式 PowerShell 下
`rm` / `del` / `Remove-Item` 会进入 wrapper,但这不是完全等价的
PowerShell `Remove-Item` 实现。

> 2026-06-11: 一次 profile.ps1 重构曾整段移除该 wrapper(当时 CI 还加了
> "Remove-Item 不应被覆盖" 的反向断言),导致 PowerShell 下删除完全绕过
> safe-rm、只剩 prompt 约束。已恢复 wrapper + alias 重绑,CI 断言改回
> 正向检查(wrapper 必须存在、5 个 alias 指向它、参数转发、-WhatIf 不落盘)。

- `function global:Remove-Item` 包装,把参数透传给
  `shellish-trash`(用 `ValueFromRemainingArguments`)
- 不加 `[CmdletBinding()]` — 否则 PS 会吞掉 `-WhatIf` / `-Verbose`
  / `-ErrorAction` 等
- 5 个 aliases (`rm` / `del` / `erase` / `rmdir` / `rd`) 全部重绑
  到 wrapper
- 用户用 `Microsoft.PowerShell.Management\Remove-Item` 全限定名
  时**绕过** wrapper — 这是设计预期,scripts / modules 明确 opt out
- 循环检测: wrapper 调 `shellish-trash.cmd` (走 cmd.exe),不触发
  PS alias 链 → 不循环
- 配合 `run.js` 已有的 PATH 注入(rm.cmd / del.cmd),cmd.exe 路径
  仍然有效

## 验收对照

- [x] agent 在 PS 7+ 用 `Remove-Item -Recurse foo` 触发 safe-rm
- [x] agent 用 `del foo` 同样拦截(走 alias → wrapper)
- [x] 用户 `y` / `a` / `N` 答正确生效(safe-rm.js 已有 confirm 流程)
- [x] agent 用 `cmd /c "rm -rf foo"` 也拦截(走 PATH rm.cmd)
- [x] 不影响其他普通 cmdlet (Get-ChildItem 等)
- [x] 脚本用全限定 cmdlet 名时可 opt out

## CI 覆盖

`test-windows.yml` 加 `Test Remove-Item wrapper is installed by
profile.ps1`:
- `Get-Command Remove-Item` 返回 `CommandType=Function`
- 5 个 aliases 全部 `Definition='Remove-Item'`

## 已知限制

- 覆盖 `Remove-Item` 是侵入式行为,会改变交互式 PowerShell session
  中 `Remove-Item` 的部分语义。
- 不支持 pipeline: `Get-ChildItem | Remove-Item` 可能不会按真实
  cmdlet 语义工作。用户需要明确传 `-Path @(Get-ChildItem)` 或文件列表,
  或使用全限定名 `Microsoft.PowerShell.Management\Remove-Item` opt out。
- 不支持 `-WhatIf`: `-WhatIf` 会被透传给 shellish-trash,
  shellish-trash 不理解该 flag,因此不能当 dry-run 使用。
- 全限定 cmdlet 名、直接 .NET / Node / Python 文件删除 API 仍可绕过。
- `cmd.exe` 内置 `del` / `rmdir` / `rd` 不一定被 PATH wrapper 拦截;
  推荐使用 `shellish-trash`。
